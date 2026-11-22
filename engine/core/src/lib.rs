//! 牛马自走棋的战斗结算（Rust 版）：只算结果，供批量模拟用。
//!
//! 规则的基准实现是 GDScript 版（`scripts/core/battle_sim.gd`、`scripts/core/card_db.gd`），这里照着它逐函数实现，
//! 靠共用用例（`tests/cases/`）和随机对拍保持逐场一致。说明见 `engine/README.md`。
//!
//! ```no_run
//! use autochess_core::{Deck, simulate};
//!
//! let deck = Deck::from_file("data/cards.json").unwrap();
//! let p1 = [deck.pick("tiger_man", "").unwrap()];
//! let p2 = [deck.pick("vulture", "").unwrap()];
//! let outcome = simulate(&deck, &p1, &p2);
//! println!("胜负 {}，P1 幸存 {:?}", outcome.winner, outcome.survivors(0));
//! ```

pub mod battle;
pub mod cards;
pub mod ids;

pub use battle::{Battle, MAX_UNITS, Outcome, Reason, Survivor, TraceStep, VERSION, simulate, simulate_traced};
pub use cards::{CardIdx, Deck, Pick};
