//! 凑齐一套阵容的期望花费（试验）：`tools/autochess_tools/economy/model.py` 里 `Plan` 的动态规划，
//! 算法和口径一一对应（改一边要改另一边），这里只算花费，给按金币搜索阵容用。
//! 花费只和"每种卡的类型、星级、张数"以及上阵人数有关，和具体是哪张卡无关，所以按这个记住算过的结果。

use std::collections::HashMap;
use std::sync::RwLock;

pub const MAX_LEVEL: usize = 7;
const STARS: usize = 5;

/// 要的一种卡：（类型 0 角色 / 1 装备, 星级, 张数）
pub type Want = (u8, u8, u8);

pub struct Economy {
    /// odds[等级-1][星级-1]
    pub odds: Vec<[f64; STARS]>,
    /// 各等级的上阵人数上限
    pub slots: Vec<usize>,
    /// xp[等级-1]：升到下一级要的经验
    pub xp: Vec<f64>,
    /// 各星级的种类数、每种的张数：[角色, 装备]
    pub kinds: [[f64; STARS]; 2],
    pub copies: [[f64; STARS]; 2],
    /// 商店里的格子数：[角色, 装备]
    pub shop: [usize; 2],
    pub refresh: f64,
    cache: RwLock<HashMap<(Vec<Want>, usize), f64>>,
}

impl Economy {
    pub fn new(
        odds: Vec<[f64; STARS]>,
        slots: Vec<usize>,
        xp: Vec<f64>,
        kinds: [[f64; STARS]; 2],
        copies: [[f64; STARS]; 2],
        shop: [usize; 2],
        refresh: f64,
    ) -> Result<Self, String> {
        if odds.len() != MAX_LEVEL || slots.len() != MAX_LEVEL || xp.len() != MAX_LEVEL - 1 {
            return Err(format!("等级是 1 到 {MAX_LEVEL}：概率、卡位各 {MAX_LEVEL} 项，经验 {} 项", MAX_LEVEL - 1));
        }
        Ok(Economy { odds, slots, xp, kinds, copies, shop, refresh, cache: RwLock::new(HashMap::new()) })
    }

    /// 能上 units 个角色的最低等级
    pub fn level_for(&self, units: usize) -> Option<usize> {
        (1..=MAX_LEVEL).find(|&level| self.slots[level - 1] >= units)
    }

    /// 从 1 级、一张都没有开始，凑齐这些卡并能上 units 个角色的最小期望花费（含买卡）；凑不齐是无穷大
    pub fn cost(&self, wants: &[Want], units: usize) -> f64 {
        let Some(need_level) = self.level_for(units) else {
            return f64::INFINITY;
        };
        let mut wants = wants.to_vec();
        wants.sort_unstable();
        let key = (wants, need_level);
        if let Some(&known) = self.cache.read().expect("没有线程会在持锁时出错").get(&key) {
            return known;
        }
        let value = self.plan(&key.0, need_level);
        self.cache.write().expect("没有线程会在持锁时出错").insert(key, value);
        value
    }

    pub fn cached(&self) -> usize {
        self.cache.read().expect("没有线程会在持锁时出错").len()
    }

    /// 状态是（等级，每种卡还缺几张），缺的张数写成混合进制数；一次刷新按格子一个一个结算
    fn plan(&self, wants: &[Want], need_level: usize) -> f64 {
        let n = wants.len();
        let mut strides = Vec::with_capacity(n);
        let mut size = 1usize;
        for want in wants {
            strides.push(size);
            size *= want.2 as usize + 1;
        }
        let mut groups: Vec<(u8, u8)> = wants.iter().map(|w| (w.0, w.1)).collect();
        groups.dedup();
        let group_of: Vec<usize> =
            wants.iter().map(|w| groups.iter().position(|g| *g == (w.0, w.1)).expect("刚放进去的")).collect();
        let pile = |kind: u8, star: u8| {
            (self.kinds[kind as usize][star as usize - 1], self.copies[kind as usize][star as usize - 1])
        };
        let group_total: Vec<f64> =
            groups.iter().map(|&(kind, star)| pile(kind, star).0 * pile(kind, star).1).collect();
        let slot_kinds: Vec<usize> = [vec![0; self.shop[0]], vec![1; self.shop[1]]].concat();
        let n_slots = slot_kinds.len();
        let price: f64 = wants.iter().map(|w| f64::from(w.1) * f64::from(w.2)).sum();

        let mut above = vec![0.0; size];
        let mut value = vec![0.0; size];
        // after[j * size + 状态]：一次刷新里看到第 j 格之前的期望
        let mut after = vec![0.0; (n_slots + 1) * size];
        let mut state = vec![0u8; n];
        let mut held = vec![0.0; groups.len()];
        let mut hits: [Vec<(f64, usize)>; 2] = [Vec::new(), Vec::new()];
        let mut tail = vec![(0.0, 1.0); n_slots + 1];
        for level in (1..=MAX_LEVEL).rev() {
            let odds = &self.odds[level - 1];
            state.fill(0);
            for index in 0..size {
                if index == 0 {
                    let best: f64 =
                        if level < need_level { self.xp[level - 1..need_level - 1].iter().sum() } else { 0.0 };
                    value[0] = best;
                    for j in 0..=n_slots {
                        after[j * size] = best;
                    }
                    continue;
                }
                for (digit, want) in state.iter_mut().zip(wants) {
                    if *digit < want.2 {
                        *digit += 1;
                        break;
                    }
                    *digit = 0;
                }
                let level_up = if level < MAX_LEVEL { self.xp[level - 1] + above[index] } else { f64::INFINITY };
                held.fill(0.0);
                for i in 0..n {
                    held[group_of[i]] += f64::from(wants[i].2 - state[i]);
                }
                let mut chance = [0.0, 0.0];
                hits[0].clear();
                hits[1].clear();
                for i in 0..n {
                    if state[i] > 0 {
                        let (kind, star, need) = wants[i];
                        let left = pile(kind, star).1 - f64::from(need - state[i]);
                        let p = odds[star as usize - 1] * left / (group_total[group_of[i]] - held[group_of[i]]);
                        if p > 0.0 {
                            chance[kind as usize] += p;
                            hits[kind as usize].push((p, index - strides[i]));
                        }
                    }
                }
                let (mut miss, mut base) = (1.0, 0.0);
                for j in (0..n_slots).rev() {
                    let kind = slot_kinds[j];
                    let next = &after[(j + 1) * size..];
                    base = hits[kind].iter().map(|&(p, k)| p * next[k]).sum::<f64>() + (1.0 - chance[kind]) * base;
                    miss *= 1.0 - chance[kind];
                    tail[j] = (base, miss);
                }
                let rolled = if miss < 1.0 { (self.refresh + base) / (1.0 - miss) } else { f64::INFINITY };
                let best = rolled.min(level_up);
                value[index] = best;
                for (j, &(base, miss)) in tail.iter().enumerate() {
                    after[j * size + index] = base + miss * best;
                }
            }
            std::mem::swap(&mut above, &mut value);
        }
        above[size - 1] + price
    }
}
