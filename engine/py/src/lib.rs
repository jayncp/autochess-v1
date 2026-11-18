//! Python 绑定（模块 `autochess_engine`）：在 Python 里批量模拟，`tools/autochess_tools/sim.py` 通过它调用 Rust 版结算。
//! 由 maturin 构建（`tools/` 里 `uv sync` 时自动编译），接口说明见 `autochess_engine.pyi`。
//!
//! 两种传阵容的方式，结果一样：
//! - `simulate`：字符串 id，`[[角色 id, 装备 id], ...]`，和 `cli/sim.gd` 的输入相同；
//! - `simulate_ids`：卡牌编号的 numpy 数组，大批量时省掉字符串转换的开销。
//!
//! 结算时释放 GIL，多核并行（rayon），结果顺序和输入一致。

use autochess_core::{Deck, MAX_UNITS, Outcome, Pick, VERSION, simulate};
use numpy::ndarray::Array2;
use numpy::{IntoPyArray, PyArray1, PyArray2, PyReadonlyArray3, PyUntypedArrayMethods};
use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;
use rayon::prelude::*;

/// 一场的结果：胜负（1/2 = 该方胜，3 = 平局）、原因（wipe / no_death）、双方幸存单位的战斗力
type Row = (u8, &'static str, Vec<i32>, Vec<i32>);
/// simulate_ids 的结果：winner、reason、p1、p2 四个数组
type Arrays<'py> =
    (Bound<'py, PyArray1<u8>>, Bound<'py, PyArray1<u8>>, Bound<'py, PyArray2<i32>>, Bound<'py, PyArray2<i32>>);

/// 结算引擎：创建时读入卡牌，之后只读，可以在多个线程里同时用
#[pyclass(frozen, module = "autochess_engine")]
struct Engine {
    deck: Deck,
}

#[pymethods]
impl Engine {
    /// cards：卡牌文件（通常是 data/cards.json）；extra_cards：额外卡牌的 JSON 文本（数组，同 id 覆盖原卡）
    #[new]
    #[pyo3(signature = (cards, extra_cards=None))]
    fn new(cards: &str, extra_cards: Option<&str>) -> PyResult<Self> {
        let mut deck = Deck::from_file(cards).map_err(PyValueError::new_err)?;
        if let Some(extra) = extra_cards {
            deck.add_json(extra, true).map_err(PyValueError::new_err)?;
        }
        Ok(Engine { deck })
    }

    /// 全部卡牌的 id，下标就是 simulate_ids 用的编号
    fn ids(&self) -> Vec<String> {
        self.deck.cards().map(|(_, card)| card.id.clone()).collect()
    }

    /// 一张卡的编号
    fn index(&self, id: &str) -> PyResult<u16> {
        self.deck.find(id).ok_or_else(|| PyValueError::new_err(format!("没有这张卡：{id}")))
    }

    /// 一批对局 [(p1, p2), ...]，阵容是 [[角色 id, 装备 id], ...]（装备为空字符串表示不带）；
    /// 返回 [(winner, reason, p1 幸存者的战斗力, p2 幸存者的战斗力), ...]。threads 为 0 时用全部核心
    #[pyo3(signature = (battles, threads=0))]
    fn simulate(&self, py: Python<'_>, battles: Vec<[Vec<[String; 2]>; 2]>, threads: usize) -> PyResult<Vec<Row>> {
        let lineup = |units: &[[String; 2]]| -> Result<Vec<Pick>, String> {
            if units.len() > MAX_UNITS {
                return Err(format!("一方最多 {MAX_UNITS} 个单位，实际 {}", units.len()));
            }
            units.iter().map(|[card, equip]| self.deck.pick(card, equip)).collect()
        };
        let picks = battles
            .iter()
            .enumerate()
            .map(|(i, [p1, p2])| {
                let both = lineup(p1).and_then(|a| Ok((a, lineup(p2)?)));
                both.map_err(|e| format!("第 {} 场：{e}", i + 1))
            })
            .collect::<Result<Vec<_>, _>>()
            .map_err(PyValueError::new_err)?;
        let deck = &self.deck;
        let outcomes = py.detach(|| {
            in_pool(threads, || picks.par_iter().map(|(p1, p2)| simulate(deck, p1, p2)).collect::<Vec<_>>())
        })?;
        Ok(outcomes.iter().map(row).collect())
    }

    /// 按编号传阵容：p1、p2 是 int32 数组，形状 (场数, 位置数, 2)，位置数不超过 7，每格是 [角色编号, 装备编号]；
    /// 角色编号为 -1 的位置跳过（阵容可以短于位置数），装备编号为 -1 表示不带。编号见 ids()、index()。
    /// 返回 (winner, reason, p1, p2)：winner 是 uint8 (场数,)，reason 是 uint8 (场数,)（0 = 全灭，1 = 连续无人阵亡），
    /// p1、p2 是 int32 (场数, 7)，幸存单位的战斗力按队列顺序排在前面，后面补 0（幸存单位的战斗力都大于 0）
    #[pyo3(signature = (p1, p2, threads=0))]
    fn simulate_ids<'py>(
        &self,
        py: Python<'py>,
        p1: PyReadonlyArray3<'py, i32>,
        p2: PyReadonlyArray3<'py, i32>,
        threads: usize,
    ) -> PyResult<Arrays<'py>> {
        let (n, width) = (p1.shape()[0], p1.shape()[1]);
        if p1.shape() != p2.shape() || p1.shape()[2] != 2 || width > MAX_UNITS {
            return Err(PyValueError::new_err(format!(
                "p1、p2 的形状应相同，为 (场数, 位置数 ≤{MAX_UNITS}, 2)，实际 {:?} 和 {:?}",
                p1.shape(),
                p2.shape()
            )));
        }
        let not_contiguous = |_| PyValueError::new_err("数组要连续存放（np.ascontiguousarray）");
        let (a, b) = (p1.as_slice().map_err(not_contiguous)?, p2.as_slice().map_err(not_contiguous)?);
        let deck = &self.deck;
        let outcomes = py
            .detach(|| {
                in_pool(threads, || {
                    (0..n)
                        .into_par_iter()
                        .map(|i| {
                            let lineup = |cells: &[i32]| -> Result<Vec<Pick>, String> {
                                let units = cells.chunks(2).filter(|unit| unit[0] >= 0);
                                units.map(|unit| deck.pick_at(i64::from(unit[0]), i64::from(unit[1]))).collect()
                            };
                            let cells = i * width * 2..(i + 1) * width * 2;
                            let (p1, p2) = (lineup(&a[cells.clone()]), lineup(&b[cells]));
                            Ok(simulate(
                                deck,
                                &p1.map_err(|e| format!("第 {} 场 P1：{e}", i + 1))?,
                                &p2.map_err(|e| format!("第 {} 场 P2：{e}", i + 1))?,
                            ))
                        })
                        .collect::<Result<Vec<Outcome>, String>>()
                })
            })?
            .map_err(PyValueError::new_err)?;
        let mut winner = Vec::with_capacity(n);
        let mut reason = Vec::with_capacity(n);
        let mut strengths = [Array2::<i32>::zeros((n, MAX_UNITS)), Array2::<i32>::zeros((n, MAX_UNITS))];
        for (i, outcome) in outcomes.iter().enumerate() {
            winner.push(outcome.winner);
            reason.push(u8::from(outcome.reason != autochess_core::Reason::Wipe));
            for (side, array) in strengths.iter_mut().enumerate() {
                for (k, unit) in outcome.survivors(side).iter().enumerate() {
                    array[[i, k]] = unit.strength;
                }
            }
        }
        let [s1, s2] = strengths;
        Ok((winner.into_pyarray(py), reason.into_pyarray(py), s1.into_pyarray(py), s2.into_pyarray(py)))
    }
}

/// threads 为 0 时用全局的线程池（全部核心），否则临时建一个这么多线程的池
fn in_pool<T: Send>(threads: usize, work: impl FnOnce() -> T + Send) -> PyResult<T> {
    if threads == 0 {
        return Ok(work());
    }
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build();
    Ok(pool.map_err(|e| PyValueError::new_err(e.to_string()))?.install(work))
}

fn row(outcome: &Outcome) -> Row {
    let strengths = |side: usize| outcome.survivors(side).iter().map(|u| u.strength).collect();
    (outcome.winner, outcome.reason.id(), strengths(0), strengths(1))
}

#[pymodule]
fn autochess_engine(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_class::<Engine>()?;
    // 和 BattleSim.VERSION 相同
    m.add("VERSION", VERSION)?;
    Ok(())
}
