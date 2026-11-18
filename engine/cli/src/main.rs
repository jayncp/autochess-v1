//! 批量模拟的命令行，输入输出和 `cli/sim.gd` 一样：
//! 读 JSONL，每行一场 `{"p1": [[角色 id, 装备 id], ...], "p2": [...]}`，可带 `"id"`；
//! 写 JSONL，每行一个结果 `{"id", "winner", "reason", "p1", "p2"}`，顺序和输入一致。
//! winner：1/2 = 该方胜，3 = 平局；reason：wipe（全灭）/ no_death（连续无人阵亡）；p1/p2 是双方幸存单位的战斗力。
//!
//! 用法：engine-cli <输入.jsonl> <输出.jsonl> [--cards <额外卡牌.json>] [--trace] [--threads N]
//! - `--cards`：额外的卡牌（JSON 数组，字段同 data/cards.json），同 id 覆盖原卡，只在本次有效
//! - `--trace`：每个结果带上简要轨迹 `"trace": [[步骤, [P1 战斗力...], [P2 战斗力...]], ...]`（每步判死之后）
//! - `--threads`：线程数，默认用全部核心

use std::process::ExitCode;
use std::time::Instant;

use autochess_core::{Deck, Outcome, Pick, TraceStep, simulate, simulate_traced};
use rayon::prelude::*;
use serde_json::{Value, json};

/// 正式卡牌数据（编译时定下仓库的位置）
const CARDS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../data/cards.json");
const USAGE: &str = "用法：engine-cli <输入.jsonl> <输出.jsonl> [--cards <额外卡牌.json>] [--trace] [--threads N]";

struct Args {
    input: String,
    output: String,
    cards: Option<String>,
    trace: bool,
    /// 0 = 用全部核心
    threads: usize,
}

/// 一场对局：输入里的 id（可以没有）和双方阵容
struct Battle {
    id: Option<Value>,
    p1: Vec<Pick>,
    p2: Vec<Pick>,
}

fn main() -> ExitCode {
    let args = match parse_args(std::env::args().skip(1).collect()) {
        Ok(args) => args,
        Err(error) => {
            eprintln!("{error}\n{USAGE}");
            return ExitCode::from(2);
        }
    };
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn parse_args(args: Vec<String>) -> Result<Args, String> {
    let mut paths = Vec::new();
    let mut parsed = Args { input: String::new(), output: String::new(), cards: None, trace: false, threads: 0 };
    let mut rest = args.into_iter();
    while let Some(arg) = rest.next() {
        match arg.as_str() {
            "--cards" => parsed.cards = Some(rest.next().ok_or("--cards 后面要写文件")?),
            "--trace" => parsed.trace = true,
            "--threads" => {
                let n = rest.next().ok_or("--threads 后面要写线程数")?;
                parsed.threads = n.parse().map_err(|_| format!("线程数不对：{n}"))?;
            }
            flag if flag.starts_with("--") => return Err(format!("不认识的参数 {flag}")),
            _ => paths.push(arg),
        }
    }
    let [input, output] = <[String; 2]>::try_from(paths).map_err(|_| "要写输入和输出两个文件")?;
    parsed.input = input;
    parsed.output = output;
    Ok(parsed)
}

fn run(args: &Args) -> Result<(), String> {
    let mut deck = Deck::from_file(CARDS)?;
    if let Some(cards) = &args.cards {
        deck.add_file(cards)?;
    }
    let text = std::fs::read_to_string(&args.input).map_err(|e| format!("读不了 {}：{e}", args.input))?;
    let lines: Vec<&str> = text.lines().filter(|line| !line.trim().is_empty()).collect();
    let pool = rayon::ThreadPoolBuilder::new().num_threads(args.threads).build().map_err(|e| e.to_string())?;
    pool.install(|| {
        let started = Instant::now();
        let battles = lines
            .par_iter()
            .enumerate()
            .map(|(i, line)| parse_battle(&deck, line).map_err(|e| format!("{} 第 {} 行：{e}", args.input, i + 1)))
            .collect::<Result<Vec<_>, _>>()?;
        let simulating = Instant::now();
        let results: Vec<(Outcome, Option<Vec<TraceStep>>)> = battles
            .par_iter()
            .map(|b| {
                if args.trace {
                    let (outcome, trace) = simulate_traced(&deck, &b.p1, &b.p2);
                    (outcome, Some(trace))
                } else {
                    (simulate(&deck, &b.p1, &b.p2), None)
                }
            })
            .collect();
        let seconds = simulating.elapsed().as_secs_f64();
        let rows: Vec<String> = battles.par_iter().zip(&results).map(|(b, (o, t))| row(b, o, t.as_deref())).collect();
        let mut out = rows.join("\n");
        if !out.is_empty() {
            out.push('\n');
        }
        std::fs::write(&args.output, out).map_err(|e| format!("写不了 {}：{e}", args.output))?;
        println!(
            "模拟 {} 场：结算 {:.2} 秒，{:.0} 场/秒（{} 线程）；连同读写共 {:.2} 秒",
            battles.len(),
            seconds,
            battles.len() as f64 / seconds.max(1e-9),
            rayon::current_num_threads(),
            started.elapsed().as_secs_f64(),
        );
        Ok(())
    })
}

fn parse_battle(deck: &Deck, line: &str) -> Result<Battle, String> {
    let value: Value = serde_json::from_str(line).map_err(|e| format!("不是合法的 JSON：{e}"))?;
    Ok(Battle { id: value.get("id").cloned(), p1: deck.lineup(&value["p1"])?, p2: deck.lineup(&value["p2"])? })
}

/// 一行结果
fn row(battle: &Battle, outcome: &Outcome, trace: Option<&[TraceStep]>) -> String {
    let strengths = |side: usize| outcome.survivors(side).iter().map(|u| u.strength).collect::<Vec<_>>();
    let mut row =
        json!({"winner": outcome.winner, "reason": outcome.reason.id(), "p1": strengths(0), "p2": strengths(1)});
    if let Some(id) = &battle.id {
        row["id"] = id.clone();
    }
    if let Some(trace) = trace {
        row["trace"] = trace.iter().map(|t| json!([t.step, t.strengths[0], t.strengths[1]])).collect();
    }
    row.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Result<Args, String> {
        parse_args(list.iter().map(|s| s.to_string()).collect())
    }

    #[test]
    fn parses_flags() {
        let parsed = args(&["in.jsonl", "--trace", "out.jsonl", "--threads", "4", "--cards", "x.json"]).unwrap();
        assert_eq!((parsed.input.as_str(), parsed.output.as_str()), ("in.jsonl", "out.jsonl"));
        assert_eq!((parsed.trace, parsed.threads, parsed.cards.as_deref()), (true, 4, Some("x.json")));
        assert_eq!(args(&["a", "b"]).unwrap().threads, 0);
    }

    #[test]
    fn rejects_bad_args() {
        assert!(args(&["only-input"]).is_err());
        assert!(args(&["a", "b", "--log"]).is_err());
        assert!(args(&["a", "b", "--threads", "many"]).is_err());
        assert!(args(&["a", "b", "--cards"]).is_err());
    }
}
