//! 试验开关：数值试验里改了口径、还没进正式规则的几条（`docs/plans/balance-tuning.md`）。
//! 用环境变量打开，进程里第一次用到时读一次；都不设时和 GDScript 版逐场一致。
//! `tools/autochess_tools/balance` 跑试验时会全部打开。

use std::env::var_os;
use std::sync::OnceLock;

macro_rules! switch {
    ($(#[$doc:meta])* $name:ident, $var:literal) => {
        $(#[$doc])*
        pub fn $name() -> bool {
            static FLAG: OnceLock<bool> = OnceLock::new();
            *FLAG.get_or_init(|| var_os($var).is_some())
        }
    };
}

switch!(
    /// 萨满：己方角色"触发"腐蚀后才加腐蚀值：这个角色一轮里的腐蚀全部结算完（含多一次）之后加一次
    raise_per_trigger,
    "AUTOCHESS_RAISE_PER_TRIGGER"
);
switch!(
    /// 炼药师：加己方全体基础技能数值之和的全部，不是一半
    full_skill_sum,
    "AUTOCHESS_FULL_SKILL_SUM"
);
switch!(
    /// 千机魔女：从装备获得的战斗力和基础技能数值是 3 倍，不是 2 倍
    triple_equipment,
    "AUTOCHESS_TRIPLE_EQUIPMENT"
);
switch!(
    /// 鹦鹉、鹦鹉手偶：额外获得对方交战位的基础技能（和已有的相加），不是变成
    copy_adds,
    "AUTOCHESS_COPY_ADD"
);
switch!(
    /// 千机之匣：开战时的战斗力也翻倍
    box_strength,
    "AUTOCHESS_BOX_STRENGTH"
);
switch!(
    /// 星辰法师（技能写 any 的 on_trigger_gain）：按结算的每一下算，不是按轮
    any_per_resolve,
    "AUTOCHESS_ANY_PER_RESOLVE"
);
