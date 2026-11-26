//! 阵容搜索：`tools/autochess_tools/balance/meta.py` 用的爬山，在这里并行做。
//! 合法、修复两条规则和 `meta.py` 的 `Space` 一一对应（改一边要改另一边），变异只在这里；
//! 每个起点各用一个随机数序列，结果和线程数无关。

use autochess_core::{Deck, MAX_UNITS, Pick, simulate};

use crate::economy::{Economy, Want};
use rayon::prelude::*;

/// 一个单位：[角色编号, 装备编号]，装备 -1 表示不带
pub type Unit = [i32; 2];
pub type Lineup = Vec<Unit>;

/// 金币约束（试验）：凑齐阵容的期望花费不超过预算，代替总星上限、卡位选择、同名上限和装备件数上限。
/// 觉醒的角色是另一张卡，按 3 张原卡算；同名的普通角色最多 2 张（第 3 张会合成觉醒），用的张数不超过牌库。
/// 规则和 `tools/autochess_tools/balance/gold.py` 的 `GoldSpace` 一一对应
pub struct Gold<'a> {
    pub economy: &'a Economy,
    pub budget: f64,
    /// 各卡的原卡编号（普通卡是它自己）
    pub base: Vec<i32>,
    /// 角色的另一个形态（普通 ↔ 觉醒），没有是 -1
    pub twin: Vec<i32>,
}

impl Gold<'_> {
    /// 要凑的卡（类型, 星级, 张数）；同名的规则不满足时没有
    fn wants(&self, star: &[i32], lineup: &[Unit]) -> Option<Vec<Want>> {
        // （类型, 原卡, 张数, 其中普通的张数）
        let mut cards: Vec<(u8, i32, u8, u8)> = Vec::with_capacity(lineup.len() * 2);
        let mut add =
            |kind: u8, card: i32, copies: u8, normal: u8| match cards.iter_mut().find(|c| c.0 == kind && c.1 == card) {
                Some(entry) => {
                    entry.2 += copies;
                    entry.3 += normal;
                }
                None => cards.push((kind, card, copies, normal)),
            };
        for &[c, e] in lineup {
            let base = self.base[c as usize];
            if base == c {
                add(0, base, 1, 1);
            } else {
                add(0, base, 3, 0);
            }
            if e >= 0 {
                add(1, e, 1, 0);
            }
        }
        let fits = |&(kind, card, copies, normal): &(u8, i32, u8, u8)| {
            normal <= 2 && f64::from(copies) <= self.economy.copies[kind as usize][star[card as usize] as usize - 1]
        };
        if !cards.iter().all(fits) {
            return None;
        }
        Some(cards.iter().map(|c| (c.0, star[c.1 as usize] as u8, c.2)).collect())
    }

    fn legal(&self, star: &[i32], lineup: &[Unit]) -> bool {
        if lineup.is_empty() || lineup.len() > MAX_UNITS {
            return false;
        }
        let Some(wants) = self.wants(star, lineup) else {
            return false;
        };
        let price: f64 = wants.iter().map(|w| f64::from(w.1) * f64::from(w.2)).sum();
        price <= self.budget && self.economy.cost(&wants, lineup.len()) <= self.budget
    }
}

/// 一个阶段的限制：能用的角色和装备、各卡的星级和同名上限、卡位选择（卡位数, 总星上限）、装备件数上限；
/// 给了 gold 就按金币约束，后三项不用
pub struct Space<'a> {
    pub chars: Vec<i32>,
    pub equips: Vec<i32>,
    pub star: Vec<i32>,
    pub limit: Vec<usize>,
    pub options: Vec<(usize, i32)>,
    pub max_equips: usize,
    pub gold: Option<Gold<'a>>,
}

/// splitmix64
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }

    fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }

    fn choice(&mut self, items: &[i32]) -> i32 {
        items[self.below(items.len())]
    }
}

fn contains(lineup: &[Unit], card: i32) -> bool {
    lineup.iter().any(|unit| unit.contains(&card))
}

impl Space<'_> {
    fn star(&self, card: i32) -> i32 {
        self.star[card as usize]
    }

    fn legal(&self, lineup: &[Unit]) -> bool {
        if let Some(gold) = &self.gold {
            return gold.legal(&self.star, lineup);
        }
        if lineup.is_empty() || lineup.iter().filter(|u| u[1] >= 0).count() > self.max_equips {
            return false;
        }
        let count = |c: i32| lineup.iter().filter(|u| u[0] == c).count();
        if lineup.iter().any(|u| count(u[0]) > self.limit[u[0] as usize]) {
            return false;
        }
        let total: i32 = lineup.iter().map(|u| self.star(u[0]) + if u[1] >= 0 { self.star(u[1]) } else { 0 }).sum();
        self.options.iter().any(|&(slots, budget)| lineup.len() <= slots && total <= budget)
    }

    fn below_star(&self, pool: &[i32], star: i32) -> Vec<i32> {
        pool.iter().copied().filter(|&x| self.star(x) < star).collect()
    }

    /// 超出限制时随机降星、去掉装备、去掉角色，直到合法；keep 是不能动的卡
    fn repair(&self, mut units: Lineup, keep: i32, rng: &mut Rng) -> Option<Lineup> {
        if let Some(gold) = &self.gold {
            return self.repair_gold(gold, units, keep, rng);
        }
        let max_slots = self.options.iter().map(|o| o.0).max().unwrap_or(0);
        for _ in 0..60 {
            if self.legal(&units) {
                return Some(units);
            }
            if units.is_empty() {
                return None;
            }
            let i = rng.below(units.len());
            let [c, e] = units[i];
            let action = rng.unit();
            if units.iter().filter(|u| u[0] == c).count() > self.limit[c as usize] {
                let same: Vec<i32> = self.chars.iter().copied().filter(|&x| self.star(x) == self.star(c)).collect();
                if !same.is_empty() {
                    units[i] = [rng.choice(&same), e];
                }
                continue;
            }
            if units.len() > max_slots || (action < 0.15 && units.len() > 1) {
                if keep != c && keep != e {
                    units.remove(i);
                }
            } else if e >= 0 && e != keep && action < 0.55 {
                let lower = self.below_star(&self.equips, self.star(e));
                units[i] = [c, if !lower.is_empty() && rng.unit() < 0.7 { rng.choice(&lower) } else { -1 }];
            } else if c != keep && self.star(c) > 1 {
                let lower = self.below_star(&self.chars, self.star(c));
                if !lower.is_empty() {
                    units[i] = [rng.choice(&lower), e];
                }
            }
        }
        None
    }

    /// 金币约束下的修复：同名超了换成同星的别的角色；超预算时随机取消觉醒、降低或去掉装备、降星、去掉角色
    fn repair_gold(&self, gold: &Gold, mut units: Lineup, keep: i32, rng: &mut Rng) -> Option<Lineup> {
        let normal = |pool: &[i32], star: i32| -> Vec<i32> {
            pool.iter().copied().filter(|&x| self.star(x) < star && gold.base[x as usize] == x).collect()
        };
        for _ in 0..80 {
            if self.legal(&units) {
                return Some(units);
            }
            if units.is_empty() {
                return None;
            }
            let i = rng.below(units.len());
            let [c, e] = units[i];
            let action = rng.unit();
            if units.len() <= MAX_UNITS && gold.wants(&self.star, &units).is_none() {
                let same: Vec<i32> = self.chars.iter().copied().filter(|&x| self.star(x) == self.star(c)).collect();
                if c != keep && !same.is_empty() {
                    units[i] = [rng.choice(&same), e];
                }
                continue;
            }
            let (fixed, twin) = (keep == c || keep == e, gold.twin[c as usize]);
            if units.len() > MAX_UNITS || (action < 0.15 && units.len() > 1) {
                if !fixed {
                    units.remove(i);
                }
            } else if gold.base[c as usize] != c && c != keep && action < 0.5 {
                units[i] = [twin, e];
            } else if e >= 0 && e != keep && action < 0.75 {
                let lower = normal(&self.equips, self.star(e));
                units[i] = [c, if !lower.is_empty() && rng.unit() < 0.7 { rng.choice(&lower) } else { -1 }];
            } else if c != keep && self.star(c) > 1 {
                let lower = normal(&self.chars, self.star(c));
                if !lower.is_empty() {
                    units[i] = [rng.choice(&lower), e];
                }
            } else if !fixed && units.len() > 1 {
                units.remove(i);
            }
        }
        None
    }

    /// 随机改一两处：换角色、换或去掉装备、换位置、换装备的宿主、增减角色。改不出合法的就原样返回
    fn mutate(&self, lineup: &[Unit], keep: i32, rng: &mut Rng) -> Lineup {
        for _ in 0..8 {
            let mut units = lineup.to_vec();
            for _ in 0..(if rng.unit() < 0.7 { 1 } else { 2 }) {
                let n = units.len();
                let i = rng.below(n);
                if let Some(gold) = &self.gold {
                    // 金币约束多两种改法：换成另一个形态（觉醒 / 取消觉醒）、让另一个位置也上这个角色
                    let extra = rng.unit();
                    let twin = gold.twin[units[i][0] as usize];
                    if extra < 0.12 && twin >= 0 {
                        units[i][0] = twin;
                        continue;
                    }
                    if extra < 0.17 && n > 1 {
                        units[rng.below(n)][0] = gold.base[units[i][0] as usize];
                        continue;
                    }
                }
                let action = rng.unit();
                if action < 0.30 {
                    units[i][0] = rng.choice(&self.chars);
                } else if action < 0.50 {
                    units[i][1] = rng.choice(&self.equips);
                } else if action < 0.56 {
                    units[i][1] = -1;
                } else if action < 0.74 && n > 1 {
                    units.swap(i, rng.below(n));
                } else if action < 0.82 && n > 1 {
                    let j = rng.below(n);
                    let (a, b) = (units[i][1], units[j][1]);
                    units[i][1] = b;
                    units[j][1] = a;
                } else if action < 0.88 && n > 1 {
                    let unit = units.remove(i);
                    units.insert(rng.below(n).min(units.len()), unit);
                } else if action < 0.94 && n > 1 {
                    units.remove(i);
                } else if n < MAX_UNITS {
                    units.insert(rng.below(n + 1), [rng.choice(&self.chars), -1]);
                }
            }
            if let Some(result) = self.repair(units, keep, rng)
                && result != lineup
                && (keep < 0 || contains(&result, keep))
            {
                return result;
            }
        }
        lineup.to_vec()
    }
}

pub fn picks(deck: &Deck, lineup: &[Unit]) -> Result<Vec<Pick>, String> {
    lineup.iter().map(|u| deck.pick_at(i64::from(u[0]), i64::from(u[1]))).collect()
}

/// 一套阵容对一批对手的得分：胜 1、平 0.5、负 0
pub fn row(deck: &Deck, mine: &[Pick], theirs: &[Vec<Pick>]) -> Vec<f64> {
    let score = |other: &Vec<Pick>| match simulate(deck, mine, other).winner {
        1 => 1.0,
        3 => 0.5,
        _ => 0.0,
    };
    theirs.iter().map(score).collect()
}

/// 每个起点做爬山：每步试 mutations 个变异，对这批对手的加权得分不降就换过去。keeps 是各起点必须带的卡（-1 不限）。
/// 返回各起点最后的阵容和得分
#[allow(clippy::too_many_arguments)]
pub fn climb(
    deck: &Deck,
    space: &Space,
    starts: &[Lineup],
    keeps: &[i32],
    opponents: &[Vec<Pick>],
    weights: &[f64],
    steps: usize,
    mutations: usize,
    seed: u64,
) -> Vec<(Lineup, f64)> {
    let value = |lineup: &Lineup| -> f64 {
        let mine = picks(deck, lineup).expect("变异出来的阵容只含合法的卡");
        row(deck, &mine, opponents).iter().zip(weights).map(|(s, w)| s * w).sum()
    };
    starts
        .par_iter()
        .zip(keeps)
        .enumerate()
        .map(|(k, (start, &keep))| {
            let mut rng = Rng(seed ^ (k as u64).wrapping_mul(0xD6E8_FEB8_6659_FD93));
            let mut current = start.clone();
            let mut best = value(&current);
            for _ in 0..steps {
                let candidates: Vec<Lineup> = (0..mutations).map(|_| space.mutate(&current, keep, &mut rng)).collect();
                let values: Vec<f64> =
                    candidates.par_iter().map(|c| if *c == current { best } else { value(c) }).collect();
                let mut top = 0;
                for (i, v) in values.iter().enumerate() {
                    if *v > values[top] {
                        top = i;
                    }
                }
                if values[top] >= best {
                    best = values[top];
                    current.clone_from(&candidates[top]);
                }
            }
            (current, best)
        })
        .collect()
}
