//! 共用用例：读 `tests/cases/` 下的规则用例和冒烟用例（和 Godot 的测试是同一份，说明见 `tests/README.md`），
//! 逐条检查，并检查交换左右后结果对称。期望值只存在用例文件里，这边不另存。

use std::path::{Path, PathBuf};

use autochess_core::{Deck, Outcome, Pick, VERSION, simulate};
use serde_json::Value;

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// 正式卡加上测试卡（`tests/cases/cards.json`）
fn deck() -> Deck {
    let mut deck = Deck::from_file(repo().join("data/cards.json")).unwrap();
    deck.add_file(repo().join("tests/cases/cards.json")).unwrap();
    deck
}

fn load_cases(name: &str) -> Vec<Value> {
    let path = repo().join("tests/cases").join(name);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("读不了 {}：{e}", path.display()));
    serde_json::from_str(&text).unwrap()
}

/// 结果，写成和用例的 expect 一样的形式（`battle_harness.gd` 的 `run` / `outcome`）
#[derive(PartialEq, Debug)]
struct Result {
    winner: i64,
    reason: Option<String>,
    p1: Vec<(String, i64)>,
    p2: Vec<(String, i64)>,
}

impl Result {
    fn of(deck: &Deck, outcome: &Outcome) -> Result {
        let side = |s: usize| {
            let units = outcome.survivors(s).iter();
            units
                .map(|u| (deck.card(u.card).id.clone(), i64::from(u.strength)))
                .collect()
        };
        Result {
            winner: outcome.winner.into(),
            reason: Some(outcome.reason.id().into()),
            p1: side(0),
            p2: side(1),
        }
    }

    /// 用例里的 expect（数可能写成小数，如 2.0）
    fn expected(value: &Value) -> Result {
        let int = |v: &Value| v.as_f64().unwrap() as i64;
        let side = |key: &str| {
            let units = value.get(key).and_then(Value::as_array).cloned().unwrap_or_default();
            units
                .iter()
                .map(|u| (u[0].as_str().unwrap().to_string(), int(&u[1])))
                .collect()
        };
        Result {
            winner: int(&value["winner"]),
            reason: value.get("reason").and_then(Value::as_str).map(String::from),
            p1: side("p1"),
            p2: side("p2"),
        }
    }

    /// 交换左右后应有的结果（`battle_harness.gd` 的 `mirror`）
    fn mirror(&self) -> Result {
        let winner = match self.winner {
            1 => 2,
            2 => 1,
            w => w,
        };
        Result {
            winner,
            reason: self.reason.clone(),
            p1: self.p2.clone(),
            p2: self.p1.clone(),
        }
    }
}

/// 跑一条用例和它的镜像，返回结果；不对称时记下问题
fn run(deck: &Deck, case: &Value, failures: &mut Vec<String>) -> Result {
    let lineup = |key: &str| -> Vec<Pick> { deck.lineup(&case[key]).unwrap() };
    let (p1, p2) = (lineup("p1"), lineup("p2"));
    let result = Result::of(deck, &simulate(deck, &p1, &p2));
    let mirrored = Result::of(deck, &simulate(deck, &p2, &p1));
    if mirrored != result.mirror() {
        failures.push(format!("[{}] 交换左右后结果不对称：{mirrored:?}", case["id"]));
    }
    result
}

fn report(kind: &str, count: usize, failures: &[String]) {
    assert!(
        failures.is_empty(),
        "{kind}：{} / {count} 条不对\n{}",
        failures.len(),
        failures.join("\n")
    );
    println!("{kind}：{count} 条通过");
}

/// 规则用例：只用测试卡，完整比较胜负、原因、双方幸存的角色和战斗力
#[test]
fn rule_cases() {
    let deck = deck();
    let cases = load_cases("battles.json");
    let mut failures = Vec::new();
    for case in &cases {
        let result = run(&deck, case, &mut failures);
        let expected = Result::expected(&case["expect"]);
        if result != expected {
            failures.push(format!("[{}] 期望 {expected:?}\n  实际 {result:?}", case["id"]));
        }
    }
    report("规则用例", cases.len(), &failures);
}

/// 冒烟用例：正式卡。关卡的解要赢（有 expect 的只比胜负），都检查左右对称
#[test]
fn smoke_cases() {
    let deck = deck();
    let cases = load_cases("smoke.json");
    let mut failures = Vec::new();
    for case in &cases {
        let result = run(&deck, case, &mut failures);
        if let Some(expect) = case.get("expect") {
            let winner = Result::expected(expect).winner;
            if result.winner != winner {
                failures.push(format!("[{}] 应该是 P{winner} 胜，实际 {result:?}", case["id"]));
            }
        }
    }
    report("冒烟用例", cases.len(), &failures);
}

/// 和 GDScript 版的事件日志版本一致：规则变了 GDScript 先加一，这里跟上
#[test]
fn version_matches_gdscript() {
    let source = std::fs::read_to_string(repo().join("scripts/core/battle_sim.gd")).unwrap();
    let line = source
        .lines()
        .find(|l| l.starts_with("const VERSION := "))
        .expect("battle_sim.gd 里应有 VERSION");
    let gdscript: i32 = line.trim_start_matches("const VERSION := ").trim().parse().unwrap();
    assert_eq!(
        VERSION, gdscript,
        "Rust 版的 VERSION 和 BattleSim.VERSION 不一致，规则改了要同步"
    );
}
