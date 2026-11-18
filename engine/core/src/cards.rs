//! 卡牌数据，对应 `scripts/core/card_db.gd`（`CardDB`）：读取 `data/cards.json` 并校验、按 id 查询、
//! 装备和角色的合并（`combine`）。字段说明见 `data/README.md`。
//!
//! 校验和 `CardDB.problems` 一致：不认识的字段、技能、参数直接报错，不静默跳过；每个技能该不该带数值是固定的，
//! 写错也在加载时报错。哪些写法合法见 `tests/cases/card_checks.json`（两边的测试共用）。

use std::collections::HashMap;
use std::path::Path;

use serde_json::{Map, Value};

use crate::battle::MAX_UNITS;
use crate::ids::{BaseSkill, CardType, Param, RACES, Scope, SkillRef, Special, Target, Timing, Timings};

/// 卡牌在 `Deck` 里的编号（按加载顺序）
pub type CardIdx = u16;

/// 卡牌的字段（`CardDB.FIELDS`）
const FIELDS: [&str; 11] = [
    "id",
    "no",
    "type",
    "star",
    "races",
    "strength",
    "timing_1",
    "timing_2",
    "skills_1",
    "skills_2",
    "special_skills",
];
const TIMING_SLOTS: [&str; 2] = ["timing_1", "timing_2"];
const SKILL_SLOTS: [&str; 2] = ["skills_1", "skills_2"];
/// 装备的格子里写"空"表示清空角色的那一格（`CardDB.CLEAR`）
const CLEAR: &str = "clear";

/// 基础技能：每种技能有没有、数值多少（GDScript 里是 `{技能 id: 数值}` 的字典）
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct BaseSkills([Option<i32>; 7]);

impl BaseSkills {
    pub fn get(&self, skill: BaseSkill) -> Option<i32> {
        self.0[skill as usize]
    }

    pub fn has(&self, skill: BaseSkill) -> bool {
        self.0[skill as usize].is_some()
    }

    pub fn set(&mut self, skill: BaseSkill, value: i32) {
        self.0[skill as usize] = Some(value);
    }

    pub fn is_empty(&self) -> bool {
        self.0.iter().all(Option::is_none)
    }

    /// 全部数值之和
    pub fn sum(&self) -> i32 {
        self.0.iter().flatten().sum()
    }

    /// 有的技能和数值，按结算顺序
    pub fn iter(&self) -> impl Iterator<Item = (BaseSkill, i32)> + '_ {
        BaseSkill::ALL.into_iter().filter_map(|s| self.get(s).map(|v| (s, v)))
    }
}

/// 特殊技能的值：词条写数值或 null（如庇护的层数、致命），描述型效果写参数
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SpecialValue {
    Value(Option<i32>),
    Params(Params),
}

/// 描述型效果的参数（`CardDB.SPECIAL_PARAMS`）。每种效果只用其中几个，没用到的是空
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct Params {
    pub timings: Timings,
    pub skill: Option<SkillRef>,
    /// 数值；获得没有数值的词条（如致命）时是 null，也是 None
    pub amount: Option<i32>,
    pub scope: Option<Scope>,
    pub timing: Option<Timing>,
    pub target: Option<Target>,
}

impl Params {
    /// 数值。只在校验过一定是数值的地方用（如队长的 amount）
    pub fn amount(&self) -> i32 {
        self.amount.expect("校验过：这里的 amount 是数值")
    }
}

/// 特殊技能：每种有没有、值是什么（GDScript 里是 `{技能 id: 值}` 的字典）
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct Specials([Option<SpecialValue>; Special::COUNT]);

impl Specials {
    pub fn has(&self, skill: Special) -> bool {
        self.0[skill as usize].is_some()
    }

    pub fn get(&self, skill: Special) -> Option<SpecialValue> {
        self.0[skill as usize]
    }

    /// 词条的数值；没有这个词条、或者写的是 null 时为 None
    pub fn value(&self, skill: Special) -> Option<i32> {
        match self.get(skill) {
            Some(SpecialValue::Value(value)) => value,
            _ => None,
        }
    }

    /// 描述型效果的参数，没有这个效果时为 None
    pub fn params(&self, skill: Special) -> Option<Params> {
        match self.get(skill) {
            Some(SpecialValue::Params(params)) => Some(params),
            _ => None,
        }
    }

    pub fn set(&mut self, skill: Special, value: SpecialValue) {
        self.0[skill as usize] = Some(value);
    }

    pub fn remove(&mut self, skill: Special) {
        self.0[skill as usize] = None;
    }

    /// 有的特殊技能和值，按 `CardDB.SPECIAL_SKILLS` 的顺序
    pub fn iter(&self) -> impl Iterator<Item = (Special, SpecialValue)> + '_ {
        Special::ALL.into_iter().filter_map(|s| self.get(s).map(|v| (s, v)))
    }
}

/// 卡牌的一格：没写（沿用角色的）、写 "clear"（清空，只有装备能写）、写了内容
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Slot<T> {
    Empty,
    Clear,
    Filled(T),
}

/// 一张卡（`data/cards.json` 的一行）
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Card {
    pub id: String,
    pub kind: CardType,
    /// 战斗力：角色必填，装备没写时为 0
    pub strength: i32,
    pub timing_slots: [Slot<Timings>; 2],
    pub skill_slots: [Slot<BaseSkills>; 2],
    pub special_skills: Slot<Specials>,
}

/// 阵容里的一个单位：角色和装备（可以不带）
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Pick {
    pub card: CardIdx,
    pub equip: Option<CardIdx>,
}

/// 角色带上装备（可为空）之后的战斗属性（`CardDB.combine` 的结果）
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Combined {
    pub strength: i32,
    pub timings: Timings,
    pub base_skills: BaseSkills,
    pub special_skills: Specials,
}

/// 全部卡牌，按 id 查询（`CardDB.all()`）
#[derive(Clone, Default, Debug)]
pub struct Deck {
    cards: Vec<Card>,
    index: HashMap<String, CardIdx>,
}

impl Deck {
    /// 读一个卡牌文件（JSON 数组，格式同 `data/cards.json`）
    pub fn from_file(path: impl AsRef<Path>) -> Result<Deck, String> {
        let mut deck = Deck::default();
        deck.load(path, false)?;
        Ok(deck)
    }

    /// 加入额外的卡牌（`CardDB.add_cards`），供平衡实验和测试使用；与已有 id 相同时覆盖原卡
    pub fn add_file(&mut self, path: impl AsRef<Path>) -> Result<(), String> {
        self.load(path, true)
    }

    /// 从 JSON 文本加入卡牌（格式同 `data/cards.json`）。replace 为假时 id 重复报错，为真时覆盖原卡
    pub fn add_json(&mut self, text: &str, replace: bool) -> Result<(), String> {
        let raw: Value = serde_json::from_str(text).map_err(|e| format!("卡牌数据不是合法的 JSON：{e}"))?;
        let Some(list) = raw.as_array() else {
            return Err("卡牌数据应为数组".into());
        };
        let mut errors = Vec::new();
        for raw in list {
            match parse_card(raw) {
                Ok(card) => {
                    if let Some(&at) = self.index.get(&card.id) {
                        if replace {
                            self.cards[at as usize] = card;
                        } else {
                            errors.push(format!("cards.json：id 重复 {}", card.id));
                        }
                    } else {
                        let at = CardIdx::try_from(self.cards.len()).map_err(|_| "卡牌太多")?;
                        self.index.insert(card.id.clone(), at);
                        self.cards.push(card);
                    }
                }
                Err(error) => errors.push(error),
            }
        }
        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors.join("\n"))
        }
    }

    fn load(&mut self, path: impl AsRef<Path>, replace: bool) -> Result<(), String> {
        let path = path.as_ref();
        let text = std::fs::read_to_string(path).map_err(|e| format!("读不了 {}：{e}", path.display()))?;
        self.add_json(&text, replace)
            .map_err(|e| format!("{}：\n{e}", path.display()))
    }

    pub fn find(&self, id: &str) -> Option<CardIdx> {
        self.index.get(id).copied()
    }

    pub fn card(&self, idx: CardIdx) -> &Card {
        &self.cards[idx as usize]
    }

    pub fn len(&self) -> usize {
        self.cards.len()
    }

    pub fn is_empty(&self) -> bool {
        self.cards.is_empty()
    }

    /// 全部卡牌，按加载顺序
    pub fn cards(&self) -> impl Iterator<Item = (CardIdx, &Card)> {
        self.cards.iter().enumerate().map(|(i, c)| (i as CardIdx, c))
    }

    /// 按 id 找到角色和装备，装备为空字符串表示不带
    pub fn pick(&self, card: &str, equip: &str) -> Result<Pick, String> {
        let find = |id: &str, kind: CardType| match self.find(id) {
            Some(idx) if self.card(idx).kind == kind => Ok(idx),
            Some(_) => Err(format!(
                "{id} 不是{}",
                if kind == CardType::Character {
                    "角色"
                } else {
                    "装备"
                }
            )),
            None => Err(format!("没有这张卡：{id}")),
        };
        let card = find(card, CardType::Character)?;
        let equip = if equip.is_empty() {
            None
        } else {
            Some(find(equip, CardType::Equipment)?)
        };
        Ok(Pick { card, equip })
    }

    /// 读一方的阵容：JSON 数组 `[[角色 id, 装备 id], ...]`，最多 `MAX_UNITS` 个
    pub fn lineup(&self, value: &Value) -> Result<Vec<Pick>, String> {
        let units = value.as_array().ok_or_else(|| format!("阵容应为数组：{value}"))?;
        if units.len() > MAX_UNITS {
            return Err(format!("一方最多 {MAX_UNITS} 个单位，实际 {}", units.len()));
        }
        units
            .iter()
            .map(|unit| match unit.as_array().map(Vec::as_slice) {
                Some([Value::String(card), Value::String(equip)]) => self.pick(card, equip),
                _ => Err(format!("阵容里的单位应为 [角色 id, 装备 id]：{unit}")),
            })
            .collect()
    }

    /// 装备像一张卡盖在角色卡上（`CardDB.combine_data`，docs/design/battle-rules.md 第 2 节）：
    /// 逐格处理，装备那一格有内容就覆盖，没有就沿用角色的，写"空"就清空；
    /// 然后两格合并：时机取并集，基础技能同名相加。战斗力不分格，角色的加上装备的。
    /// 千机之匣、千机魔女的翻倍在这里算（只算战斗用的数，卡面上印的数是 GDScript 的事）
    pub fn combine(&self, pick: Pick) -> Combined {
        let c = self.card(pick.card);
        let e = pick.equip.map(|i| self.card(i));
        let mut timings = Timings::default();
        for k in 0..2 {
            if let Some(t) = overlay(c.timing_slots[k], e.map(|e| e.timing_slots[k])) {
                timings = timings.union(t);
            }
        }
        let special = overlay(c.special_skills, e.map(|e| e.special_skills)).unwrap_or_default();
        let mut sums = [0; 7];
        for k in 0..2 {
            let Some(skills) = overlay(c.skill_slots[k], e.map(|e| e.skill_slots[k])) else {
                continue;
            };
            let times = skill_times(&special, e, k);
            for (skill, value) in skills.iter() {
                sums[skill as usize] += value * times;
            }
        }
        // 数值不大于 0 的去掉
        let mut base_skills = BaseSkills::default();
        for skill in BaseSkill::ALL {
            if sums[skill as usize] > 0 {
                base_skills.set(skill, sums[skill as usize]);
            }
        }
        Combined {
            strength: c.strength + e.map_or(0, |e| e.strength) * equipment_times(&special),
            timings,
            base_skills,
            special_skills: special,
        }
    }
}

/// 合并后第 k 格基础技能的倍数（`CardDB.skill_times`）：千机之匣（自身的基础技能数值翻倍）两格都 ×2；
/// 千机魔女（从装备获得的翻倍）装备填了的那格 ×2。special 是合并后的特殊技能：被装备覆盖掉就没有这个效果
fn skill_times(special: &Specials, e: Option<&Card>, k: usize) -> i32 {
    let mut times = if special.has(Special::DoubleSkills) { 2 } else { 1 };
    if e.is_some_and(|e| matches!(e.skill_slots[k], Slot::Filled(_))) {
        times *= equipment_times(special);
    }
    times
}

/// 装备的战斗力的倍数（`CardDB.equipment_times`，千机魔女 ×2）
fn equipment_times(special: &Specials) -> i32 {
    if special.has(Special::DoubleEquipment) { 2 } else { 1 }
}

/// 一格的叠放结果（`CardDB._overlay`）：装备有这格（写了内容或 "clear"）就用装备的，否则沿用角色的；
/// "clear" 和没写都是空（None）
fn overlay<T: Copy>(c: Slot<T>, e: Option<Slot<T>>) -> Option<T> {
    let slot = match e {
        Some(Slot::Empty) | None => c,
        Some(slot) => slot,
    };
    match slot {
        Slot::Filled(value) => Some(value),
        _ => None,
    }
}

// ---------- 读取和校验（CardDB._normalize、_check、_check_params） ----------

/// 解析一张卡并校验，有问题时列出全部问题
fn parse_card(raw: &Value) -> Result<Card, String> {
    let Some(c) = raw.as_object() else {
        return Err(format!("cards.json：卡牌应为字典：{raw}"));
    };
    let id = c.get("id").and_then(Value::as_str).unwrap_or_default().to_string();
    let mut bad = Vec::new();
    if id.is_empty() {
        bad.push("缺少 id".to_string());
    }
    for field in c.keys() {
        if !FIELDS.contains(&field.as_str()) {
            bad.push(format!("未知字段 {field}"));
        }
    }
    let kind = c.get("type").and_then(Value::as_str).and_then(CardType::from_id);
    if kind.is_none() {
        bad.push(format!("类型 {}", show(c.get("type"))));
    }
    for field in ["no", "star", "strength"] {
        if c.get(field).is_some_and(|v| int(v).is_none()) {
            bad.push(format!("{field} 应为整数"));
        }
    }
    if kind == Some(CardType::Character) && !c.contains_key("strength") {
        bad.push("角色缺少战斗力".into());
    }
    match c.get("races") {
        None => {}
        Some(Value::Array(races)) => {
            for race in races {
                if !race.as_str().is_some_and(|r| RACES.contains(&r)) {
                    bad.push(format!("种族 {race}"));
                }
            }
        }
        Some(other) => bad.push(format!("races 应为列表：{other}")),
    }
    for slot in TIMING_SLOTS.into_iter().chain(SKILL_SLOTS).chain(["special_skills"]) {
        if c.get(slot).and_then(Value::as_str) == Some(CLEAR) && kind != Some(CardType::Equipment) {
            bad.push(format!("只有装备能写\"空\"：{slot}"));
        }
    }
    let timing_slots = TIMING_SLOTS.map(|slot| parse_slot(c, slot, &mut bad, parse_timings_slot));
    let skill_slots = SKILL_SLOTS.map(|slot| parse_slot(c, slot, &mut bad, parse_base_skills));
    let special_skills = parse_slot(c, "special_skills", &mut bad, parse_specials);
    if !bad.is_empty() {
        return Err(format!("cards.json：{id} 有误：{}", bad.join(", ")));
    }
    Ok(Card {
        id,
        kind: kind.expect("上面校验过"),
        strength: c.get("strength").and_then(int).unwrap_or(0),
        timing_slots,
        skill_slots,
        special_skills,
    })
}

/// 一格：没写是空，"clear" 是清空，其余交给 parse；技能字典写 {} 和没写等价（`CardDB._normalize`）
fn parse_slot<T>(
    c: &Map<String, Value>,
    slot: &str,
    bad: &mut Vec<String>,
    parse: fn(&str, &Value, &mut Vec<String>) -> Option<T>,
) -> Slot<T> {
    match c.get(slot) {
        None => Slot::Empty,
        Some(Value::String(s)) if s == CLEAR => Slot::Clear,
        Some(Value::Object(m)) if m.is_empty() => Slot::Empty,
        Some(value) => parse(slot, value, bad).map_or(Slot::Empty, Slot::Filled),
    }
}

fn parse_timings_slot(slot: &str, value: &Value, bad: &mut Vec<String>) -> Option<Timings> {
    let timings = parse_timings(value);
    if timings.is_none() {
        bad.push(format!("{slot} 应为时机的列表或 \"clear\"：{value}"));
    }
    timings
}

/// 时机的列表：不空、不重复，都是已知的时机（`CardDB._valid_timings`）
fn parse_timings(value: &Value) -> Option<Timings> {
    let list = value.as_array()?;
    let mut timings = Timings::default();
    for v in list {
        let timing = Timing::from_id(v.as_str()?)?;
        if timings.has(timing) {
            return None;
        }
        timings.add(timing);
    }
    (!timings.is_empty()).then_some(timings)
}

fn parse_base_skills(slot: &str, value: &Value, bad: &mut Vec<String>) -> Option<BaseSkills> {
    let Some(dict) = value.as_object() else {
        bad.push(format!("{slot} 应为技能字典或 \"clear\""));
        return None;
    };
    let mut skills = BaseSkills::default();
    for (key, v) in dict {
        match (BaseSkill::from_id(key), positive(v)) {
            (None, _) => bad.push(format!("技能 {key}")),
            (Some(_), None) => bad.push(format!("{key} 应为正整数")),
            (Some(skill), Some(n)) => skills.set(skill, n),
        }
    }
    Some(skills)
}

fn parse_specials(slot: &str, value: &Value, bad: &mut Vec<String>) -> Option<Specials> {
    let Some(dict) = value.as_object() else {
        bad.push(format!("{slot} 应为技能字典或 \"clear\""));
        return None;
    };
    let mut specials = Specials::default();
    for (key, v) in dict {
        let Some(skill) = Special::from_id(key) else {
            bad.push(format!("技能 {key}"));
            continue;
        };
        if !skill.params().is_empty() {
            match parse_params(v, skill) {
                Ok(params) => specials.set(skill, SpecialValue::Params(params)),
                Err(error) => bad.push(format!("{key} 的参数{error}")),
            }
        } else if skill.valued() {
            // 带数值的词条：正整数
            match positive(v) {
                Some(n) => specials.set(skill, SpecialValue::Value(Some(n))),
                None => bad.push(format!("{key} 应为正整数")),
            }
        } else if v.is_null() {
            specials.set(skill, SpecialValue::Value(None));
        } else if let Some(n) = int(v) {
            // 不带数值的词条写了数值：只看有没有（和 GDScript 版一样不报错）
            specials.set(skill, SpecialValue::Value(Some(n)));
        } else {
            bad.push(format!("{key} 应为 null"));
        }
    }
    Some(specials)
}

/// 特殊技能的参数字典：正好是这几个参数，取值合法（`CardDB._check_params`）。
/// amount 写 null 只用于不带数值的词条，获得（grant）不带数值的词条时必须写 null
fn parse_params(value: &Value, effect: Special) -> Result<Params, String> {
    let keys = effect.params();
    let names: Vec<&str> = keys.iter().map(|k| k.id()).collect();
    let Some(dict) = value
        .as_object()
        .filter(|d| d.len() == keys.len() && names.iter().all(|n| d.contains_key(*n)))
    else {
        return Err(format!("应为 {names:?}"));
    };
    let mut params = Params::default();
    for &key in keys {
        let v = &dict[key.id()];
        let ok = match key {
            Param::Timings => parse_timings(v).map(|t| params.timings = t).is_some(),
            Param::Skill => parse_skill_ref(v).map(|s| params.skill = Some(s)).is_some(),
            Param::Amount => {
                // skill 在 amount 之前校验过
                let valueless = matches!(params.skill, Some(SkillRef::Special(s)) if !s.valued());
                params.amount = positive(v);
                if effect == Special::Grant && valueless {
                    v.is_null()
                } else {
                    params.amount.is_some() || (v.is_null() && valueless)
                }
            }
            Param::Scope => v
                .as_str()
                .and_then(Scope::from_id)
                .map(|s| params.scope = Some(s))
                .is_some(),
            Param::Timing => v
                .as_str()
                .and_then(Timing::from_id)
                .map(|t| params.timing = Some(t))
                .is_some(),
            Param::Target => v
                .as_str()
                .and_then(Target::from_id)
                .map(|t| params.target = Some(t))
                .is_some(),
        };
        if !ok {
            return Err(format!(" {} 不对：{v}", key.id()));
        }
    }
    Ok(params)
}

/// 参数 skill：基础技能、"any"，或者没有参数的特殊技能（获得的词条）
fn parse_skill_ref(value: &Value) -> Option<SkillRef> {
    let id = value.as_str()?;
    if let Some(skill) = BaseSkill::from_id(id) {
        return Some(SkillRef::Base(skill));
    }
    if id == "any" {
        return Some(SkillRef::Any);
    }
    Special::from_id(id)
        .filter(|s| s.params().is_empty())
        .map(SkillRef::Special)
}

/// 正整数（基础技能、带数值的词条、参数 amount 的数值）
fn positive(value: &Value) -> Option<i32> {
    int(value).filter(|&n| n > 0)
}

/// JSON 的数：整数，或者写成小数的整数（Godot 写出的 JSON 里数都是小数，如 2.0）
pub(crate) fn int(value: &Value) -> Option<i32> {
    if let Some(n) = value.as_i64() {
        return i32::try_from(n).ok();
    }
    let f = value.as_f64()?;
    (f.fract() == 0.0 && f.abs() <= f64::from(i32::MAX)).then_some(f as i32)
}

fn show(value: Option<&Value>) -> String {
    value.map_or("（没写）".into(), Value::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repo() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
    }

    fn deck() -> Deck {
        let mut deck = Deck::from_file(repo().join("data/cards.json")).unwrap();
        deck.add_file(repo().join("tests/cases/cards.json")).unwrap();
        deck
    }

    fn combine(deck: &Deck, card: &str, equip: &str) -> Combined {
        deck.combine(deck.pick(card, equip).unwrap())
    }

    fn skills(pairs: &[(BaseSkill, i32)]) -> BaseSkills {
        let mut skills = BaseSkills::default();
        for &(s, v) in pairs {
            skills.set(s, v);
        }
        skills
    }

    #[test]
    fn formal_cards_load() {
        let deck = Deck::from_file(repo().join("data/cards.json")).unwrap();
        assert!(deck.len() > 100);
        assert!(deck.find("tiger_man").is_some());
    }

    /// 卡牌数据的校验（`tests/cases/card_checks.json`，和 GDScript 版共用）：ok 的要通过，其余每张都要报错
    #[test]
    fn card_checks() {
        let text = std::fs::read_to_string(repo().join("tests/cases/card_checks.json")).unwrap();
        let entries: Vec<Value> = serde_json::from_str(&text).unwrap();
        let mut failures = Vec::new();
        for entry in &entries {
            let result = Deck::default().add_json(&format!("[{}]", entry["card"]), false);
            match (entry["ok"].as_bool().unwrap(), result) {
                (true, Err(error)) => failures.push(format!("{}：应该通过，实际报 {error}", entry["note"])),
                (false, Ok(())) => failures.push(format!("{}：应该报错，实际通过", entry["note"])),
                _ => {}
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[test]
    fn rejects_duplicate_ids() {
        let card = r#"{"id": "x", "type": "character", "strength": 3}"#;
        let error = Deck::default()
            .add_json(&format!("[{card}, {card}]"), false)
            .unwrap_err();
        assert!(error.contains("id 重复 x"), "{error}");
    }

    #[test]
    fn extra_cards_replace() {
        let mut deck = deck();
        let before = deck.len();
        deck.add_json(r#"[{"id": "t_tiger", "type": "character", "strength": 99}]"#, true)
            .unwrap();
        assert_eq!(deck.len(), before);
        assert_eq!(combine(&deck, "t_tiger", "").strength, 99);
    }

    #[test]
    fn combine_overlays_slots() {
        let deck = deck();
        // 装备的战斗力加到角色上，没写的格子沿用角色的
        let tiger = combine(&deck, "t_tiger", "t_wooden_sword");
        assert_eq!(tiger.strength, 9);
        assert!(tiger.timings.has(Timing::OnEngage));
        assert_eq!(tiger.base_skills, skills(&[(BaseSkill::Rage, 2)]));
        // 装备写"空"清空角色的那一格
        let hollow = combine(&deck, "t_tiger", "t_hollow");
        assert!(hollow.base_skills.is_empty());
        assert_eq!(hollow.strength, 16);
        let void = combine(&deck, "t_toad", "t_void_heart");
        assert_eq!(void.special_skills, Specials::default());
    }

    #[test]
    fn combine_doubles() {
        let deck = deck();
        // 千机之匣：自身的基础技能翻倍
        let boxed = combine(&deck, "t_soldier", "t_clockwork_box");
        assert_eq!(boxed.base_skills, skills(&[(BaseSkill::Rally, 4)]));
        assert_eq!(boxed.strength, 3);
        // 千机魔女：装备的战斗力和装备那一格的基础技能翻倍
        let witch = combine(&deck, "t_clockwork_witch", "t_wooden_sword");
        assert_eq!(witch.strength, 15 + 10);
        assert_eq!(witch.base_skills, skills(&[(BaseSkill::Rally, 2)]));
    }
}
