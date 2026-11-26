//! 各种 id，对应 `scripts/core/card_db.gd` 开头的常量。
//!
//! 每种 id 是一个枚举，`ALL` 按 `CardDB` 里的顺序列出全部取值，`id()` 是数据里写的英文 id。
//! 基础技能的顺序也是结算的顺序（`BattleSim` 按它分拍）。

/// 时机（`CardDB.TIMINGS`）
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Timing {
    PreBattle,
    OnEnter,
    OnEngage,
}

impl Timing {
    pub const ALL: [Timing; 3] = [Timing::PreBattle, Timing::OnEnter, Timing::OnEngage];

    pub fn id(self) -> &'static str {
        match self {
            Timing::PreBattle => "pre_battle",
            Timing::OnEnter => "on_enter",
            Timing::OnEngage => "on_engage",
        }
    }

    pub fn from_id(id: &str) -> Option<Timing> {
        Timing::ALL.into_iter().find(|t| t.id() == id)
    }
}

/// 一组时机（GDScript 里是时机的列表；这里只关心有没有，不关心顺序和重复）
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct Timings(u8);

impl Timings {
    pub fn has(self, timing: Timing) -> bool {
        self.0 & (1 << timing as u8) != 0
    }

    pub fn add(&mut self, timing: Timing) {
        self.0 |= 1 << timing as u8;
    }

    /// 并集
    pub fn union(self, other: Timings) -> Timings {
        Timings(self.0 | other.0)
    }

    pub fn is_empty(self) -> bool {
        self.0 == 0
    }
}

/// 基础技能（`CardDB.BASE_SKILLS`），顺序就是结算顺序：作用对象由近及远，先加后减，财富最后
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum BaseSkill {
    Rage,
    Rally,
    Support,
    Inspire,
    Corrode,
    Annihilate,
    Wealth,
}

impl BaseSkill {
    pub const ALL: [BaseSkill; 7] = [
        BaseSkill::Rage,
        BaseSkill::Rally,
        BaseSkill::Support,
        BaseSkill::Inspire,
        BaseSkill::Corrode,
        BaseSkill::Annihilate,
        BaseSkill::Wealth,
    ];

    pub fn id(self) -> &'static str {
        match self {
            BaseSkill::Rage => "rage",
            BaseSkill::Rally => "rally",
            BaseSkill::Support => "support",
            BaseSkill::Inspire => "inspire",
            BaseSkill::Corrode => "corrode",
            BaseSkill::Annihilate => "annihilate",
            BaseSkill::Wealth => "wealth",
        }
    }

    pub fn from_id(id: &str) -> Option<BaseSkill> {
        BaseSkill::ALL.into_iter().find(|s| s.id() == id)
    }
}

/// 特殊技能（`CardDB.SPECIAL_SKILLS`）：词条和描述型效果，顺序同 `CardDB`
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Special {
    Backlash,
    Sturdy,
    Assist,
    ImmuneLethal,
    /// 己方角色触发〈技能〉时，该角色战斗力 +N
    OnTriggerBoost,
    Awaken,
    Shelter,
    Bless,
    Lethal,
    /// 己方角色触发〈技能〉时，自身战斗力 +N
    OnTriggerGain,
    OnResolveBonus,
    /// 战前时点里受到的伤害减半（过了庇护、坚固之后，四舍五入）
    HalvePreBattleDamage,
    /// 己方角色触发〈技能〉后，己方全体的〈技能〉值 +N
    OnTriggerRaise,
    /// 己方角色结算〈技能〉时，自身战斗力 +N
    OnResolveGain,
    /// 对方角色结算〈技能〉时，己方全体战斗力 +N
    OnEnemyResolveGainAll,
    ExtraResolve,
    ExtraRound,
    DoubleSkills,
    /// 从装备获得的战斗力和基础技能数值变为 N 倍
    EquipmentTimes,
    CopySkills,
    Grant,
    ClearSkills,
    RaiseSkills,
    GainSkillSum,
    GainAllIfOutnumbered,
    DamageHalfStrength,
    /// 〈时机〉对方交战位的战斗力高于自身时，对它造成一次致命伤害（庇护能挡，对免疫致命的是 0 点）
    Execute,
}

impl Special {
    pub const COUNT: usize = 27;
    pub const ALL: [Special; Special::COUNT] = [
        Special::Backlash,
        Special::Sturdy,
        Special::Assist,
        Special::ImmuneLethal,
        Special::OnTriggerBoost,
        Special::Awaken,
        Special::Shelter,
        Special::Bless,
        Special::Lethal,
        Special::OnTriggerGain,
        Special::OnResolveBonus,
        Special::HalvePreBattleDamage,
        Special::OnTriggerRaise,
        Special::OnResolveGain,
        Special::OnEnemyResolveGainAll,
        Special::ExtraResolve,
        Special::ExtraRound,
        Special::DoubleSkills,
        Special::EquipmentTimes,
        Special::CopySkills,
        Special::Grant,
        Special::ClearSkills,
        Special::RaiseSkills,
        Special::GainSkillSum,
        Special::GainAllIfOutnumbered,
        Special::DamageHalfStrength,
        Special::Execute,
    ];

    pub fn id(self) -> &'static str {
        match self {
            Special::Backlash => "backlash",
            Special::Sturdy => "sturdy",
            Special::Assist => "assist",
            Special::ImmuneLethal => "immune_lethal",
            Special::OnTriggerBoost => "on_trigger_boost",
            Special::Awaken => "awaken",
            Special::Shelter => "shelter",
            Special::Bless => "bless",
            Special::Lethal => "lethal",
            Special::OnTriggerGain => "on_trigger_gain",
            Special::OnResolveBonus => "on_resolve_bonus",
            Special::HalvePreBattleDamage => "halve_pre_battle_damage",
            Special::OnTriggerRaise => "on_trigger_raise",
            Special::OnResolveGain => "on_resolve_gain",
            Special::OnEnemyResolveGainAll => "on_enemy_resolve_gain_all",
            Special::ExtraResolve => "extra_resolve",
            Special::ExtraRound => "extra_round",
            Special::DoubleSkills => "double_skills",
            Special::EquipmentTimes => "equipment_times",
            Special::CopySkills => "copy_skills",
            Special::Grant => "grant",
            Special::ClearSkills => "clear_skills",
            Special::RaiseSkills => "raise_skills",
            Special::GainSkillSum => "gain_skill_sum",
            Special::GainAllIfOutnumbered => "gain_all_if_outnumbered",
            Special::DamageHalfStrength => "damage_half_strength",
            Special::Execute => "execute",
        }
    }

    pub fn from_id(id: &str) -> Option<Special> {
        Special::ALL.into_iter().find(|s| s.id() == id)
    }

    /// 带数值的词条（`CardDB.VALUED_KEYWORDS`，如庇护的层数）：数值是正整数；其余词条不带数值，写 null
    pub fn valued(self) -> bool {
        matches!(self, Special::Backlash | Special::Sturdy | Special::Shelter)
    }

    /// 写成参数字典的特殊技能有哪些参数（`CardDB.SPECIAL_PARAMS`）；其余的写数值或 null，返回空
    pub fn params(self) -> &'static [Param] {
        use Param::*;
        match self {
            Special::Awaken => &[Timings],
            Special::Bless => &[Timings, Amount],
            Special::OnTriggerGain
            | Special::OnTriggerBoost
            | Special::OnTriggerRaise
            | Special::OnResolveGain
            | Special::OnResolveBonus
            | Special::OnEnemyResolveGainAll => &[Skill, Amount],
            Special::ExtraResolve => &[Scope, Skill],
            Special::ExtraRound => &[Scope, Timing],
            Special::EquipmentTimes => &[Amount],
            Special::CopySkills | Special::GainSkillSum | Special::DamageHalfStrength | Special::Execute => &[Timings],
            Special::Grant => &[Timings, Target, Skill, Amount],
            Special::ClearSkills => &[Timings, Target],
            Special::RaiseSkills => &[Timings, Skill, Amount],
            Special::GainAllIfOutnumbered => &[Timings, Amount],
            _ => &[],
        }
    }
}

/// 特殊技能的参数名（`CardDB.SPECIAL_PARAMS` 里的值）
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Param {
    Timings,
    Skill,
    Amount,
    Scope,
    Timing,
    Target,
}

impl Param {
    pub fn id(self) -> &'static str {
        match self {
            Param::Timings => "timings",
            Param::Skill => "skill",
            Param::Amount => "amount",
            Param::Scope => "scope",
            Param::Timing => "timing",
            Param::Target => "target",
        }
    }
}

/// 一组特殊技能（只记有没有），如单位的带时机的特殊技能（`Unit.timed_specials`）
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct SpecialSet(u32);

impl SpecialSet {
    pub fn has(self, skill: Special) -> bool {
        self.0 & (1 << skill as u32) != 0
    }

    pub fn add(&mut self, skill: Special) {
        self.0 |= 1 << skill as u32;
    }

    pub fn union(self, other: SpecialSet) -> SpecialSet {
        SpecialSet(self.0 | other.0)
    }

    pub fn is_empty(self) -> bool {
        self.0 == 0
    }
}

/// 参数 skill 的取值：基础技能、"any"（任意 / 所有基础技能，`CardDB.ANY`），或获得的词条
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SkillRef {
    Base(BaseSkill),
    Any,
    Special(Special),
}

/// 被动的范围（`CardDB.SCOPES`）：自身、己方全体、开战时位于己方第 1 位的角色、
/// 自身和开战时位于己方第 2 位的角色、自身和队列里紧挨在前面的那一位
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Scope {
    Itself,
    Allies,
    First,
    ItselfAndSecond,
    ItselfAndFront,
}

impl Scope {
    pub const ALL: [Scope; 5] =
        [Scope::Itself, Scope::Allies, Scope::First, Scope::ItselfAndSecond, Scope::ItselfAndFront];

    pub fn id(self) -> &'static str {
        match self {
            Scope::Itself => "self",
            Scope::Allies => "allies",
            Scope::First => "first",
            Scope::ItselfAndSecond => "self_and_second",
            Scope::ItselfAndFront => "self_and_front",
        }
    }

    pub fn from_id(id: &str) -> Option<Scope> {
        Scope::ALL.into_iter().find(|s| s.id() == id)
    }
}

/// 对象（`CardDB.TARGETS`）：自身、下一位、下两位、己方全体、对方全体、对方前两位；
/// 下四位、对方前四位是觉醒试验用的，现在只有 Rust 版认
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Target {
    Own,
    Next,
    NextTwo,
    Allies,
    Enemies,
    EnemyFirstTwo,
    NextFour,
    EnemyFirstFour,
}

impl Target {
    pub const ALL: [Target; 8] = [
        Target::Own,
        Target::Next,
        Target::NextTwo,
        Target::Allies,
        Target::Enemies,
        Target::EnemyFirstTwo,
        Target::NextFour,
        Target::EnemyFirstFour,
    ];

    pub fn id(self) -> &'static str {
        match self {
            Target::Own => "self",
            Target::Next => "next",
            Target::NextTwo => "next_two",
            Target::Allies => "allies",
            Target::Enemies => "enemies",
            Target::EnemyFirstTwo => "enemy_first_two",
            Target::NextFour => "next_four",
            Target::EnemyFirstFour => "enemy_first_four",
        }
    }

    pub fn from_id(id: &str) -> Option<Target> {
        Target::ALL.into_iter().find(|t| t.id() == id)
    }
}

/// 种族（`CardDB.RACES`），只用于校验数据
pub const RACES: [&str; 6] = ["beast", "human", "elf", "divine", "nature", "treasure"];

/// 卡牌类型（`CardDB.TYPES`）
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CardType {
    Character,
    Equipment,
}

impl CardType {
    pub fn from_id(id: &str) -> Option<CardType> {
        match id {
            "character" => Some(CardType::Character),
            "equipment" => Some(CardType::Equipment),
            _ => None,
        }
    }
}
