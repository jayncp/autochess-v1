//! 战斗结算，对应 `scripts/core/battle_sim.gd`（`BattleSim`），规则见 `docs/design/battle-rules.md`。
//!
//! 结构和函数名照抄 GDScript 版，每个函数的注释里写着对应的 GDScript 函数，改规则时逐函数对照。只换了数据表示：
//! - 单位放在一个定长数组里，用下标（`UnitId`）指代；双方队列（`fields`）和各种单位的列表都是下标的定长列表（`Line`），
//!   一场战斗不分配堆内存。
//! - 只算结果（胜负、原因、幸存单位的战斗力），不产生事件日志。GDScript 里只为事件日志服务的部分
//!   （uid、效果的来源、多一轮和多一次来自哪个单位）省略，只留下数量。
//! - 双方用 0、1 表示（GDScript 是 1、2）；胜负的取值和 GDScript 一样：1/2 = 该方胜，3 = 平局。

use crate::cards::{BaseSkills, CardIdx, Deck, Params, Pick, SpecialValue, Specials};
use crate::ids::{BaseSkill, Scope, SkillRef, Special, SpecialSet, Target, Timing, Timings};

/// 和 `BattleSim.VERSION` 相同（测试会检查），规则变化时 GDScript 版先加一
pub const VERSION: i32 = 9;
/// 致命的攻击值
pub const LETHAL_ATTACK: i32 = 10000;
/// 平局：连续多少次交战无人阵亡
pub const NO_DEATH_ENGAGES: u32 = 20;
/// 一方最多几个单位
pub const MAX_UNITS: usize = 7;

/// 一个时点里特殊技能的步骤（battle-rules.md 4.1）：记 → 增 → 删 → 改 → 加 → 减 → 醒，之后才是基础技能。
/// 每一步列出属于它的带时机的特殊技能，双方同时结算；被动不占步骤，挂在事件上
/// （`on_resolve`、`on_trigger`、`after_trigger`、`hit`、`resolve_beats` 里的多一次、`resolve_timing` 里的多一轮、`damage` 里的减半）。
/// "记"这一步只读取场面（`record_special`），后面的步骤按记录结算，所以记下的效果也列在它生效的那一步里
const STEPS: [(Step, &[Special]); 7] = [
    (
        Step::Record,
        &[
            Special::CopySkills,
            Special::GainSkillSum,
            Special::GainAllIfOutnumbered,
            Special::DamageHalfStrength,
            Special::Execute,
        ],
    ),
    (Step::Grant, &[Special::Bless, Special::Grant, Special::CopySkills]),
    (Step::Clear, &[Special::ClearSkills]),
    (Step::Raise, &[Special::RaiseSkills]),
    (Step::Gain, &[Special::GainSkillSum, Special::GainAllIfOutnumbered]),
    (Step::Damage, &[Special::DamageHalfStrength, Special::Execute]),
    (Step::Awaken, &[Special::Awaken]),
];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Step {
    Record,
    Grant,
    Clear,
    Raise,
    Gain,
    Damage,
    Awaken,
}

/// 按方记下持有者的特殊技能：被动（不带时机的描述型特殊技能，挂在事件上）和协战
const INDEXED: [Special; 9] = [
    Special::OnTriggerGain,
    Special::OnTriggerBoost,
    Special::OnTriggerRaise,
    Special::OnResolveGain,
    Special::OnResolveBonus,
    Special::OnEnemyResolveGainAll,
    Special::ExtraResolve,
    Special::ExtraRound,
    Special::Assist,
];

/// 单位在 `Battle.units` 里的下标：第 side 方开战时第 index 位是 side × MAX_UNITS + index
pub type UnitId = u8;

/// 结束的原因：全灭，或连续 `NO_DEATH_ENGAGES` 次交战无人阵亡
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub enum Reason {
    #[default]
    Wipe,
    NoDeath,
}

impl Reason {
    pub fn id(self) -> &'static str {
        match self {
            Reason::Wipe => "wipe",
            Reason::NoDeath => "no_death",
        }
    }
}

/// 定长的单位列表（最多 `MAX_UNITS` 个），保持顺序。可以复制，遍历时先复制一份，不妨碍改单位
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct Line {
    ids: [UnitId; MAX_UNITS],
    len: u8,
}

impl Line {
    fn push(&mut self, u: UnitId) {
        self.ids[self.len as usize] = u;
        self.len += 1;
    }

    pub fn len(&self) -> usize {
        self.len as usize
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// 第 k 个，没有则为 None
    pub fn get(&self, k: usize) -> Option<UnitId> {
        (k < self.len()).then(|| self.ids[k])
    }

    pub fn first(&self) -> Option<UnitId> {
        self.get(0)
    }

    pub fn contains(&self, u: UnitId) -> bool {
        self.into_iter().any(|x| x == u)
    }

    fn position(&self, u: UnitId) -> Option<usize> {
        self.into_iter().position(|x| x == u)
    }

    /// 满足条件的那些，顺序不变
    fn filter(&self, keep: impl Fn(UnitId) -> bool) -> Line {
        let mut line = Line::default();
        for u in *self {
            if keep(u) {
                line.push(u);
            }
        }
        line
    }

    /// 前 n 个
    fn take(&self, n: usize) -> Line {
        let mut line = *self;
        line.len = line.len.min(n as u8);
        line
    }
}

impl IntoIterator for Line {
    type Item = UnitId;
    type IntoIter = std::iter::Take<std::array::IntoIter<UnitId, MAX_UNITS>>;

    fn into_iter(self) -> Self::IntoIter {
        self.ids.into_iter().take(self.len as usize)
    }
}

/// 战斗中的一个单位（`BattleSim.Unit`）
#[derive(Clone, Copy, Default, Debug)]
struct Unit {
    /// 哪一方：0 / 1
    side: usize,
    /// 初始序号：开战时在第几位（从 0 数）
    index: usize,
    card: CardIdx,
    strength: i32,
    timings: Timings,
    base_skills: BaseSkills,
    special_skills: Specials,
    /// 在哪些时机触发：自己的时机，加上带时机的特殊技能的时机
    acting_timings: Timings,
    /// 带时机的特殊技能（没有的跳过特殊技能的各步）
    timed_specials: SpecialSet,
    /// 千机之匣：战斗力和基础技能在合并装备时已经翻倍；战斗中获得、被加的基础技能数值也 ×2（获得的战斗力不翻倍）
    doubled: bool,
    done_pre_battle: bool,
    done_entering: bool,
}

impl Unit {
    /// `Unit._init`
    fn new(deck: &Deck, side: usize, index: usize, pick: Pick) -> Unit {
        let stats = deck.combine(pick);
        let mut acting_timings = stats.timings;
        let mut timed_specials = SpecialSet::default();
        for (skill, value) in stats.special_skills.iter() {
            if let SpecialValue::Params(params) = value
                && !params.timings.is_empty()
            {
                acting_timings = acting_timings.union(params.timings);
                timed_specials.add(skill);
            }
        }
        Unit {
            side,
            index,
            card: pick.card,
            strength: stats.strength,
            timings: stats.timings,
            base_skills: stats.base_skills,
            special_skills: stats.special_skills,
            acting_timings,
            timed_specials,
            doubled: stats.special_skills.has(Special::DoubleSkills),
            done_pre_battle: false,
            done_entering: false,
        }
    }

    fn acts_at(&self, timing: Timing) -> bool {
        self.acting_timings.has(timing)
    }
}

/// 一方被动和协战的持有者：特殊技能 -> 持有者，按队列顺序（`BattleSim._holders[side]`）
#[derive(Clone, Copy, Default, Debug)]
struct Holders([Line; Special::COUNT]);

impl Holders {
    fn has(&self, skill: Special) -> bool {
        !self.0[skill as usize].is_empty()
    }

    fn of(&self, skill: Special) -> Line {
        self.0[skill as usize]
    }
}

/// 一个单位这一轮"记"下的场面（`BattleSim._records` 里它的几条记录）
#[derive(Clone, Copy, Default, Debug)]
struct Records {
    /// 鹦鹉：对方交战位此刻的基础技能
    copy_skills: BaseSkills,
    /// 炼药师：己方全体基础技能数值之和
    skill_sum: i32,
    /// 对方人数比己方多
    outnumbered: bool,
    /// 沼泽之王：对方交战位，和它此刻战斗力的一半
    half_strength: Option<(UnitId, i32)>,
    /// 眼镜王蛇：对方交战位，此刻战斗力高于自身时才有
    execute: Option<UnitId>,
}

/// 幸存的一个单位
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct Survivor {
    pub card: CardIdx,
    pub strength: i32,
}

/// 一场的结果
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Outcome {
    /// 1/2 = 该方胜，3 = 平局
    pub winner: u8,
    pub reason: Reason,
    survivors: [[Survivor; MAX_UNITS]; 2],
    counts: [u8; 2],
}

impl Outcome {
    /// 一方（0 / 1）幸存的单位，按队列顺序
    pub fn survivors(&self, side: usize) -> &[Survivor] {
        &self.survivors[side][..self.counts[side] as usize]
    }
}

/// 算完整场战斗（`BattleSim.simulate`）。一方超过 `MAX_UNITS` 个单位时 panic（用 `Deck::lineup` 读的阵容已经检查过）
pub fn simulate(deck: &Deck, p1: &[Pick], p2: &[Pick]) -> Outcome {
    let mut battle = Battle::new(deck, p1, p2);
    battle.run();
    battle.outcome()
}

/// 算一场，同时记下简要轨迹（只用于和 GDScript 版对拍时定位第一处不同，不追求速度）
pub fn simulate_traced(deck: &Deck, p1: &[Pick], p2: &[Pick]) -> (Outcome, Vec<TraceStep>) {
    let mut battle = Battle::new(deck, p1, p2);
    battle.trace = Some(Vec::new());
    battle.run();
    (battle.outcome(), battle.trace.take().unwrap_or_default())
}

/// 简要轨迹的一步：哪一步（pre_battle / enter / engage，同事件日志的类型），判死之后双方队列里每个角色的战斗力。
/// GDScript 版由事件日志算出同样的东西（`cli/sim.gd --trace`）
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct TraceStep {
    pub step: &'static str,
    pub strengths: [Vec<i32>; 2],
}

/// 一场战斗的状态（`BattleSim`）
#[derive(Clone, Debug)]
pub struct Battle {
    units: [Unit; 2 * MAX_UNITS],
    /// 双方队列，第 0 个是交战位
    fields: [Line; 2],
    /// 0 = 未结束，1/2 = 该方胜，3 = 平局
    pub winner: u8,
    pub reason: Reason,
    no_death_engages: u32,
    holders: [Holders; 2],
    /// 正在结算的时点，不在时点里（对撞、协战、反噬）是 None（`BattleSim._timing`）
    timing: Option<Timing>,
    /// 简要轨迹，打开时才记（`simulate_traced`）
    trace: Option<Vec<TraceStep>>,
}

impl Battle {
    /// `BattleSim._init`
    pub fn new(deck: &Deck, p1: &[Pick], p2: &[Pick]) -> Battle {
        let mut battle = Battle {
            units: [Unit::default(); 2 * MAX_UNITS],
            fields: [Line::default(); 2],
            winner: 0,
            reason: Reason::Wipe,
            no_death_engages: 0,
            holders: [Holders::default(); 2],
            timing: None,
            trace: None,
        };
        for (side, lineup) in [p1, p2].into_iter().enumerate() {
            assert!(lineup.len() <= MAX_UNITS, "一方最多 {MAX_UNITS} 个单位，实际 {}", lineup.len());
            for (index, &pick) in lineup.iter().enumerate() {
                let u = (side * MAX_UNITS + index) as UnitId;
                battle.units[u as usize] = Unit::new(deck, side, index, pick);
                battle.fields[side].push(u);
            }
            battle.index_holders(side);
        }
        battle
    }

    pub fn outcome(&self) -> Outcome {
        let mut outcome = Outcome {
            winner: self.winner,
            reason: self.reason,
            survivors: [[Survivor::default(); MAX_UNITS]; 2],
            counts: [0; 2],
        };
        for side in 0..2 {
            for (k, u) in self.fields[side].into_iter().enumerate() {
                let unit = &self.units[u as usize];
                outcome.survivors[side][k] = Survivor { card: unit.card, strength: unit.strength };
            }
            outcome.counts[side] = self.fields[side].len;
        }
        outcome
    }

    fn unit(&self, u: UnitId) -> &Unit {
        &self.units[u as usize]
    }

    fn unit_mut(&mut self, u: UnitId) -> &mut Unit {
        &mut self.units[u as usize]
    }

    /// 一方的交战位（只在双方都有人时调用）
    fn front(&self, side: usize) -> UnitId {
        self.fields[side].first().expect("双方都有人")
    }

    /// `BattleSim.run`
    pub fn run(&mut self) {
        self.pre_battle_phase();
        if self.winner == 0 {
            self.main_phase();
        }
    }

    /// 战前阶段：第 k 步取双方各自第 k 个未执行过的单位，在战前触发的按 resolve_timing 结算，之后判死
    /// （`BattleSim.pre_battle_phase`）
    fn pre_battle_phase(&mut self) {
        while !self.check_winner() {
            let mut pair = [None; 2];
            for (side, slot) in pair.iter_mut().enumerate() {
                for u in self.fields[side] {
                    if !self.unit(u).done_pre_battle {
                        self.unit_mut(u).done_pre_battle = true;
                        *slot = Some(u);
                        break;
                    }
                }
            }
            if pair == [None, None] {
                return;
            }
            let mut actors = Line::default();
            for u in pair.into_iter().flatten() {
                if self.unit(u).acts_at(Timing::PreBattle) {
                    actors.push(u);
                }
            }
            self.resolve_timing(actors, Timing::PreBattle);
            self.settle_death();
            self.record_trace("pre_battle");
        }
    }

    /// 主循环：有未触发的入场就先入场，否则交战；每步之后判死。
    /// 有人阵亡则"无人阵亡"计数清零，否则每次交战加一（入场不算）（`BattleSim.main_phase`）
    fn main_phase(&mut self) {
        while !self.check_winner() {
            let mut engaged = false;
            if !self.entering_step() {
                self.engage_step();
                engaged = true;
            }
            let died = self.settle_death();
            self.record_trace(if engaged { "engage" } else { "enter" });
            if died {
                self.no_death_engages = 0;
            } else if engaged {
                self.no_death_engages += 1;
            }
        }
    }

    /// 简要轨迹：判死之后记下这一步和双方每个角色的战斗力（只在 trace 打开时）
    fn record_trace(&mut self, step: &'static str) {
        if self.trace.is_none() {
            return;
        }
        let strengths = [0, 1].map(|side| self.fields[side].into_iter().map(|u| self.unit(u).strength).collect());
        if let Some(trace) = &mut self.trace {
            trace.push(TraceStep { step, strengths });
        }
    }

    /// 双方交战位里在入场时触发、还没入场的单位执行入场；都没有则返回 false（`BattleSim.entering_step`）
    fn entering_step(&mut self) -> bool {
        let mut actors = Line::default();
        for side in 0..2 {
            let front = self.front(side);
            if self.unit(front).acts_at(Timing::OnEnter) && !self.unit(front).done_entering {
                self.unit_mut(front).done_entering = true;
                actors.push(front);
            }
        }
        if actors.is_empty() {
            return false;
        }
        self.resolve_timing(actors, Timing::OnEnter);
        true
    }

    /// 交战：在交战时触发的交战位按 resolve_timing 结算；双方都活着则对撞，再结算协战、反噬（`BattleSim.engage_step`）
    fn engage_step(&mut self) {
        let fronts = [self.front(0), self.front(1)];
        let mut actors = Line::default();
        for u in fronts {
            if self.unit(u).acts_at(Timing::OnEngage) {
                actors.push(u);
            }
        }
        self.resolve_timing(actors, Timing::OnEngage);
        if fronts.iter().any(|&u| self.unit(u).strength <= 0) {
            return;
        }
        // 致命：攻击视为无穷大；对方免疫致命时按普通对撞算
        let mut attacks = [0; 2];
        for (k, attack) in attacks.iter_mut().enumerate() {
            let (me, other) = (self.unit(fronts[k]), self.unit(fronts[1 - k]));
            let lethal = me.special_skills.has(Special::Lethal) && !other.special_skills.has(Special::ImmuneLethal);
            *attack = if lethal { LETHAL_ATTACK } else { me.strength };
        }
        self.damage(fronts[0], attacks[1]);
        self.damage(fronts[1], attacks[0]);
        if self.holders[0].has(Special::Assist) || self.holders[1].has(Special::Assist) {
            self.assist(fronts);
        }
        for u in fronts {
            if self.unit(u).special_skills.has(Special::Backlash) {
                let amount = self.unit(u).special_skills.value(Special::Backlash).expect("校验过：反噬是正整数");
                self.damage(u, amount);
            }
        }
    }

    /// 协战：对撞之后，双方第 2 位起从前往后，同一位置上双方同时；对方交战位受到等于持有者战斗力的伤害
    /// （持有者战斗力 ≤0 也照常，伤害不大于 0 就是 0）。持有者在交战位时不生效（`BattleSim.assist`）
    fn assist(&mut self, fronts: [UnitId; 2]) {
        let depth = self.fields[0].len().max(self.fields[1].len());
        for k in 1..depth {
            for side in 0..2 {
                if let Some(holder) = self.fields[side].get(k)
                    && self.unit(holder).special_skills.has(Special::Assist)
                {
                    self.damage(fronts[1 - side], self.unit(holder).strength.max(0));
                }
            }
        }
    }

    /// 一个时间节点（docs/design/battle-rules.md 4.1）：一轮从上到下是
    /// 特殊技能的各步 → 被唤醒的单位结算基础技能 → 原本在这个时机触发的单位结算基础技能。
    /// 每组都按拍结算，每拍双方同时，拍的顺序就是 `BaseSkill::ALL`。中途不判死。
    /// 多一轮：有多一轮的单位把整轮再走一遍（来源相加），别的单位等着（`BattleSim.resolve_timing`）
    fn resolve_timing(&mut self, actors: Line, timing: Timing) {
        self.timing = Some(timing);
        let mut extra = [0; MAX_UNITS]; // 第 i 个单位多几轮
        let mut rounds = 1;
        if self.holders[0].has(Special::ExtraRound) || self.holders[1].has(Special::ExtraRound) {
            for (i, u) in actors.into_iter().enumerate() {
                extra[i] = self.extra_rounds(u, timing);
                rounds = rounds.max(extra[i] + 1);
            }
        }
        for r in 0..rounds {
            let mut group = Line::default();
            for (i, u) in actors.into_iter().enumerate() {
                if extra[i] >= r {
                    group.push(u);
                }
            }
            let woken = self.special_steps(group, timing);
            self.resolve_beats(woken);
            let own = group.filter(|u| self.unit(u).timings.has(timing));
            self.resolve_beats(own);
        }
        self.timing = None;
    }

    /// 被动：〈范围〉〈时机〉多触发一轮（extra_round），返回给 u 带来几轮（每个持有者一轮）。
    /// 范围：自身；己方全体；开战时位于己方第 1 位的角色（持有者自己在第 1 位时没有效果）；
    /// 自身和开战时位于己方第 2 位的角色（持有者自己在第 2 位时只算一次）；
    /// 自身和队列里紧挨在自己前面的那一位（按当时的队列）（`BattleSim._extra_rounds`）
    fn extra_rounds(&self, u: UnitId, timing: Timing) -> usize {
        let unit = self.unit(u);
        let mut count = 0;
        for holder in self.holders[unit.side].of(Special::ExtraRound) {
            let params = self.passive(holder, Special::ExtraRound);
            if params.timing != Some(timing) {
                continue;
            }
            let counts = match params.scope.expect("校验过") {
                Scope::Itself => holder == u,
                Scope::Allies => true,
                Scope::First => unit.index == 0 && holder != u,
                Scope::ItselfAndSecond => holder == u || unit.index == 1,
                Scope::ItselfAndFront => holder == u || self.next_unit(u) == Some(holder),
            };
            if counts {
                count += params.times();
            }
        }
        count
    }

    /// 一组单位按拍结算基础技能（`BattleSim.resolve_beats`）。
    /// 一个单位的一个技能在一轮里：结算一下（连同"结算时"的被动）→ "触发时"的被动（一轮一次）→
    /// 多一次：同一拍里接着再结算，每一下分开走伤害流程、数值每次重新读、各带"结算时"的被动 →
    /// 全部结算完，"触发后"的被动（一轮一次）
    fn resolve_beats(&mut self, units: Line) {
        for skill in BaseSkill::ALL {
            for u in units {
                let Some(value) = self.unit(u).base_skills.get(skill) else {
                    continue;
                };
                self.apply_skill(u, skill, value);
                self.on_resolve(u, skill);
                self.on_trigger(u, skill);
                if self.holders[self.unit(u).side].has(Special::ExtraResolve) {
                    for _ in 0..self.extra_resolves(u, skill) {
                        let value = self.unit(u).base_skills.get(skill).expect("结算中不会失去基础技能");
                        self.apply_skill(u, skill, value);
                        self.on_resolve(u, skill);
                    }
                }
                self.after_trigger(u, skill);
            }
        }
    }

    /// 被动：〈范围〉〈技能〉多结算一次（extra_resolve），返回给 u 带来几次（每个持有者一次）。
    /// 范围：自身；己方全体（`BattleSim._extra_resolves`）
    fn extra_resolves(&self, u: UnitId, skill: BaseSkill) -> usize {
        let side = self.unit(u).side;
        self.holders[side]
            .of(Special::ExtraResolve)
            .into_iter()
            .map(|holder| {
                let params = self.passive(holder, Special::ExtraResolve);
                let counts =
                    params.skill == Some(SkillRef::Base(skill)) && (params.scope == Some(Scope::Allies) || holder == u);
                if counts { params.times() } else { 0 }
            })
            .sum()
    }

    /// 特殊技能的各步：双方带这个时机的特殊技能按 STEPS 的顺序结算。返回被唤醒的单位（`BattleSim.special_steps`）
    fn special_steps(&mut self, actors: Line, timing: Timing) -> Line {
        let mut woken = Line::default();
        let mut present = SpecialSet::default();
        for u in actors {
            present = present.union(self.unit(u).timed_specials);
        }
        if present.is_empty() {
            return woken;
        }
        let mut records = [Records::default(); MAX_UNITS]; // 第 i 个单位这一轮记下的场面
        for (step, skills) in STEPS {
            for &skill in skills {
                if !present.has(skill) {
                    continue;
                }
                for (i, u) in actors.into_iter().enumerate() {
                    let Some(params) = self.unit(u).special_skills.params(skill) else {
                        continue;
                    };
                    if !params.timings.has(timing) {
                        continue;
                    }
                    if step == Step::Record {
                        self.record_special(u, skill, &mut records[i]);
                    } else {
                        self.apply_special(u, skill, params, &records[i], &mut woken);
                    }
                }
            }
        }
        woken
    }

    /// "记"：读取并固定要用到的场面，这一轮后面的步骤按这份记录算（双方都有时各按各的记录，互不影响）
    /// （`BattleSim.record_special`）
    fn record_special(&self, u: UnitId, skill: Special, records: &mut Records) {
        let side = self.unit(u).side;
        let enemies = self.fields[1 - side];
        match skill {
            Special::CopySkills => {
                // 鹦鹉：对方交战位此刻的基础技能（卡面上的数，千机之匣已经翻倍）
                records.copy_skills = enemies.first().map(|e| self.unit(e).base_skills).unwrap_or_default();
            }
            Special::GainSkillSum => {
                // 炼药师：己方全体基础技能数值之和（含财富）
                records.skill_sum = self.fields[side].into_iter().map(|p| self.unit(p).base_skills.sum()).sum();
            }
            Special::GainAllIfOutnumbered => {
                records.outnumbered = enemies.len() > self.fields[side].len();
            }
            Special::DamageHalfStrength => {
                // 沼泽之王：对方交战位此刻战斗力的一半，四舍五入
                records.half_strength = enemies.first().map(|e| (e, round_half(self.unit(e).strength.max(0))));
            }
            Special::Execute => {
                let own = self.unit(u).strength;
                records.execute = enemies.first().filter(|&e| self.unit(e).strength > own);
            }
            _ => unreachable!("{} 没有记录", skill.id()),
        }
    }

    /// 对象：自身、下一位、下两位（队列里排在自己后面的两位）、己方全体、对方全体、对方前两位（`BattleSim.targets`）
    fn targets(&self, u: UnitId, target: Target) -> Line {
        let side = self.unit(u).side;
        match target {
            Target::Own => {
                let mut line = Line::default();
                line.push(u);
                line
            }
            Target::Next => {
                let mut line = Line::default();
                if let Some(next) = self.next_unit(u) {
                    line.push(next);
                }
                line
            }
            Target::NextTwo | Target::NextFour => {
                let mut line = Line::default();
                let own = self.fields[side];
                let count = if target == Target::NextTwo { 2 } else { 4 };
                if let Some(position) = own.position(u) {
                    for k in 1..=count {
                        if let Some(next) = own.get(position + k) {
                            line.push(next);
                        }
                    }
                }
                line
            }
            Target::Allies => self.fields[side],
            Target::Enemies => self.fields[1 - side],
            Target::EnemyFirstTwo => self.fields[1 - side].take(2),
            Target::EnemyFirstFour => self.fields[1 - side].take(4),
        }
    }

    /// 结算一个带时机的特殊技能；被唤醒的单位加进 woken（`BattleSim.apply_special`）
    fn apply_special(&mut self, u: UnitId, skill: Special, params: Params, records: &Records, woken: &mut Line) {
        let side = self.unit(u).side;
        match skill {
            Special::Bless => {
                // 神佑：下一位获得 N 层庇护（层数叠加）
                if let Some(next) = self.next_unit(u) {
                    self.grant(next, SkillRef::Special(Special::Shelter), params.amount);
                }
            }
            Special::Grant => {
                // 〈对象〉获得〈技能或词条〉：没有的加上，已有的数值相加
                for t in self.targets(u, params.target.expect("校验过")) {
                    self.grant(t, params.skill.expect("校验过"), params.amount);
                }
            }
            Special::CopySkills => {
                // 鹦鹉：额外获得一份对方交战位的基础技能（和已有的相加，同"获得"）
                for _ in 0..params.times() {
                    for skill in BaseSkill::ALL {
                        if let Some(value) = records.copy_skills.get(skill) {
                            self.grant(u, SkillRef::Base(skill), Some(value));
                        }
                    }
                }
            }
            Special::ClearSkills => {
                // 美杜莎女王：清除对方前两位的基础技能（特殊技能不受影响）
                for t in self.targets(u, params.target.expect("校验过")) {
                    self.unit_mut(t).base_skills = BaseSkills::default();
                }
            }
            Special::RaiseSkills => {
                // 风滚草：己方全体的〈技能〉值 +N，只加已经有这个技能的；"any" 是所有基础技能
                for t in self.fields[side] {
                    for s in BaseSkill::ALL {
                        let matches = params.skill == Some(SkillRef::Any) || params.skill == Some(SkillRef::Base(s));
                        if self.unit(t).base_skills.has(s) && matches {
                            self.raise(t, s, params.amount());
                        }
                    }
                }
            }
            Special::GainSkillSum => {
                if records.skill_sum > 0 {
                    self.buff(u, records.skill_sum);
                }
            }
            Special::GainAllIfOutnumbered => {
                // 神裁者：对方角色多于己方时，己方全体战斗力 +N
                if records.outnumbered {
                    for t in self.fields[side] {
                        self.buff(t, params.amount());
                    }
                }
            }
            Special::DamageHalfStrength => {
                if let Some((target, amount)) = records.half_strength {
                    self.damage(target, amount);
                }
            }
            Special::Execute => {
                // 致命伤害：庇护能挡（消耗一层）；对免疫致命的单位是 0 点，不消耗庇护
                if let Some(target) = records.execute
                    && !self.unit(target).special_skills.has(Special::ImmuneLethal)
                {
                    self.damage(target, LETHAL_ATTACK);
                }
            }
            Special::Awaken => {
                if let Some(next) = self.next_unit(u) {
                    woken.push(next);
                }
            }
            _ => unreachable!("未知的带时机的特殊技能 {}", skill.id()),
        }
    }

    /// 记下一方被动和协战的持有者。被动在持有者还在队列中时生效，同名的各自生效（`BattleSim._index_holders`）。
    /// 只在开战和这一方有人阵亡时重建：战斗中获得的协战要等到那时才算进来，和 GDScript 版一样
    fn index_holders(&mut self, side: usize) {
        let mut holders = Holders::default();
        for u in self.fields[side] {
            for skill in INDEXED {
                if self.unit(u).special_skills.has(skill) {
                    holders.0[skill as usize].push(u);
                }
            }
        }
        self.holders[side] = holders;
    }

    /// 被动的参数（持有者一定有这个被动）
    fn passive(&self, holder: UnitId, skill: Special) -> Params {
        self.unit(holder).special_skills.params(skill).expect("持有者有这个被动")
    }

    /// 一方带某个被动、技能对得上的持有者和数值（参数里的 skill 是这个技能，或任意基础技能）（`BattleSim._passive_holders`）
    fn passive_holders(&self, side: usize, passive: Special, skill: BaseSkill) -> impl Iterator<Item = (UnitId, i32)> {
        self.holders[side].of(passive).into_iter().filter_map(move |holder| {
            let params = self.passive(holder, passive);
            let wanted = params.skill == Some(SkillRef::Base(skill)) || params.skill == Some(SkillRef::Any);
            wanted.then(|| (holder, params.amount()))
        })
    }

    /// "结算时"的被动，每一下都算（含多一次的每一下）（`BattleSim._on_resolve`）：
    /// 己方角色结算〈技能〉时，自身战斗力 +N（on_resolve_gain，星辰法师）；
    /// 对方角色结算〈技能〉时，己方全体战斗力 +N（on_enemy_resolve_gain_all，八咫镜，由对方的持有者结算）
    fn on_resolve(&mut self, u: UnitId, skill: BaseSkill) {
        let side = self.unit(u).side;
        let mut gains = [0; 2 * MAX_UNITS];
        for (holder, amount) in self.passive_holders(side, Special::OnResolveGain, skill) {
            gains[holder as usize] += amount;
        }
        for (_, amount) in self.passive_holders(1 - side, Special::OnEnemyResolveGainAll, skill) {
            for t in self.fields[1 - side] {
                gains[t as usize] += amount;
            }
        }
        self.buff_all(gains);
    }

    /// "触发时"的被动，一个角色的一个技能一轮算一次（多一次不算新的触发）（`BattleSim._on_trigger`）：
    /// 己方角色触发〈技能〉时，自身战斗力 +N（on_trigger_gain，沼泽触手）；该角色战斗力 +N（on_trigger_boost，队长）
    fn on_trigger(&mut self, u: UnitId, skill: BaseSkill) {
        let side = self.unit(u).side;
        let mut gains = [0; 2 * MAX_UNITS];
        for (holder, amount) in self.passive_holders(side, Special::OnTriggerGain, skill) {
            gains[holder as usize] += amount;
        }
        for (_, amount) in self.passive_holders(side, Special::OnTriggerBoost, skill) {
            gains[u as usize] += amount;
        }
        self.buff_all(gains);
    }

    /// "触发后"的被动：己方角色触发〈技能〉后，己方全体的〈技能〉值 +N（on_trigger_raise，萨满）。
    /// 这个角色这一轮的这个技能全部结算完（含多一次）之后加一次，只加有这个技能的（`BattleSim._after_trigger`）
    fn after_trigger(&mut self, u: UnitId, skill: BaseSkill) {
        let side = self.unit(u).side;
        let total: i32 = self.passive_holders(side, Special::OnTriggerRaise, skill).map(|(_, amount)| amount).sum();
        if total == 0 {
            return;
        }
        for t in self.fields[side] {
            if self.unit(t).base_skills.has(skill) {
                self.raise(t, skill, total);
            }
        }
    }

    /// 按单位加战斗力（gains 的下标是 `UnitId`）
    fn buff_all(&mut self, gains: [i32; 2 * MAX_UNITS]) {
        for (unit, gain) in self.units.iter_mut().zip(gains) {
            unit.strength += gain;
        }
    }

    /// 队列里紧挨在后面的己方单位，没有则返回 None（`BattleSim.next_unit`）
    fn next_unit(&self, u: UnitId) -> Option<UnitId> {
        let line = self.fields[self.unit(u).side];
        line.get(line.position(u)? + 1)
    }

    /// 结算一条基础技能（`BattleSim.apply_skill`）
    fn apply_skill(&mut self, u: UnitId, skill: BaseSkill, value: i32) {
        let side = self.unit(u).side;
        let enemies = self.fields[1 - side];
        match skill {
            BaseSkill::Rage => self.buff(u, value),
            BaseSkill::Rally => {
                let total = self.fields[side]
                    .into_iter()
                    .map(|p| self.unit(p).base_skills.get(BaseSkill::Rally).unwrap_or(0))
                    .sum();
                self.buff(u, total);
            }
            BaseSkill::Support => {
                if let Some(next) = self.next_unit(u) {
                    self.buff(next, value);
                }
            }
            BaseSkill::Inspire => {
                for t in self.fields[side] {
                    self.buff(t, value);
                }
            }
            BaseSkill::Corrode => {
                if let Some(front) = enemies.first() {
                    self.hit(u, front, value, skill);
                }
            }
            BaseSkill::Annihilate => {
                for t in enemies {
                    self.hit(u, t, value, skill);
                }
            }
            BaseSkill::Wealth => {} // 只做特效，不改战力
        }
    }

    /// 腐蚀、湮灭的一下。被动：己方角色结算〈技能〉时，伤害 +N（on_resolve_bonus，如蟾蜍），
    /// 加在这一下上再进伤害流程，卡面数值不变（`BattleSim._hit`）
    fn hit(&mut self, u: UnitId, target: UnitId, value: i32, skill: BaseSkill) {
        let side = self.unit(u).side;
        let mut bonus = 0;
        for holder in self.holders[side].of(Special::OnResolveBonus) {
            let params = self.passive(holder, Special::OnResolveBonus);
            if params.skill == Some(SkillRef::Base(skill)) {
                bonus += params.amount();
            }
        }
        self.damage(target, value + bonus);
    }

    /// 获得基础技能或词条：没有的加上，已有的数值相加；没有数值的词条（致命）amount 是 None（battle-rules.md 6.4）。
    /// 带千机之匣的角色获得的基础技能数值 ×2（`BattleSim.grant`）
    fn grant(&mut self, target: UnitId, skill: SkillRef, amount: Option<i32>) {
        let t = self.unit_mut(target);
        match skill {
            SkillRef::Base(s) => {
                let mut amount = amount.expect("校验过：获得基础技能时 amount 是数值");
                if t.doubled {
                    amount *= 2;
                }
                t.base_skills.set(s, t.base_skills.get(s).unwrap_or(0) + amount);
            }
            SkillRef::Special(s) => {
                // 带数值的词条从 0 加起；不带数值的词条 amount 是 None（校验保证获得时写 null）
                let value = amount.map(|a| t.special_skills.value(s).unwrap_or(0) + a);
                t.special_skills.set(s, SpecialValue::Value(value));
            }
            // GDScript 版会在特殊技能里写一个 "any"，没有任何效果
            SkillRef::Any => {}
        }
    }

    /// 改基础技能的数值，只改已经有的；带千机之匣的角色 ×2（`BattleSim.raise`）
    fn raise(&mut self, target: UnitId, skill: BaseSkill, amount: i32) {
        let t = self.unit_mut(target);
        let amount = if t.doubled { amount * 2 } else { amount };
        let value = t.base_skills.get(skill).expect("只改已经有的") + amount;
        t.base_skills.set(skill, value);
    }

    /// `BattleSim.buff`
    fn buff(&mut self, target: UnitId, amount: i32) {
        self.unit_mut(target).strength += amount;
    }

    /// 伤害流程：有庇护就挡下这次伤害、消耗一层（先于坚固）→ 否则减去坚固（最低 0）→
    /// 战前时点里带"战前时点受到的伤害减半"的再减半（四舍五入）→ 扣战力（`BattleSim.damage`）
    fn damage(&mut self, target: UnitId, amount: i32) {
        let pre_battle = self.timing == Some(Timing::PreBattle);
        let t = self.unit_mut(target);
        let sheltered = amount > 0 && t.special_skills.has(Special::Shelter);
        let mut dealt = 0;
        if sheltered {
            let layers = t.special_skills.value(Special::Shelter).expect("校验过：庇护的层数是正整数") - 1;
            if layers <= 0 {
                t.special_skills.remove(Special::Shelter);
            } else {
                t.special_skills.set(Special::Shelter, SpecialValue::Value(Some(layers)));
            }
        } else {
            let sturdy = t.special_skills.value(Special::Sturdy).unwrap_or(0); // 没有坚固是 0
            dealt = (amount - sturdy).max(0);
            if pre_battle && t.special_skills.has(Special::HalvePreBattleDamage) {
                dealt = round_half(dealt);
            }
        }
        t.strength -= dealt;
    }

    /// 判死：一次性移除双方所有战力 ≤0 的单位，返回是否有人阵亡（`BattleSim.settle_death`）
    fn settle_death(&mut self) -> bool {
        let mut any = false;
        for side in 0..2 {
            let alive = self.fields[side].filter(|u| self.unit(u).strength > 0);
            if alive.len() < self.fields[side].len() {
                self.fields[side] = alive;
                self.index_holders(side);
                any = true;
            }
        }
        any
    }

    /// 判胜负和平局，返回是否结束（`BattleSim.check_winner`）。
    /// 平局：双方同时全灭，或连续 NO_DEATH_ENGAGES 次交战无人阵亡（只在主循环里计数）
    fn check_winner(&mut self) -> bool {
        let (winner, reason) = match (self.fields[0].is_empty(), self.fields[1].is_empty()) {
            (true, true) => (3, Reason::Wipe),
            (false, true) => (1, Reason::Wipe),
            (true, false) => (2, Reason::Wipe),
            _ if self.no_death_engages >= NO_DEATH_ENGAGES => (3, Reason::NoDeath),
            _ => return false,
        };
        self.winner = winner;
        self.reason = reason;
        true
    }
}

/// 一半，四舍五入（0.5 远离零，同 GDScript 的 `roundi(x / 2.0)`）
fn round_half(x: i32) -> i32 {
    (f64::from(x) / 2.0).round() as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_half_matches_gdscript() {
        // roundi 是 0.5 远离零
        let cases = [(0, 0), (1, 1), (2, 1), (3, 2), (5, 3), (-1, -1), (-3, -2), (-4, -2)];
        for (x, expected) in cases {
            assert_eq!(round_half(x), expected, "round_half({x})");
        }
    }
}
