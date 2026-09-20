class_name EnemyMechanics
extends RefCounted
## 怪物专属机制的**参数装配表**。
##
## ## 为什么单独成文件
##
## `_apply_mechanic` 是 **208 行**的 match 大表——53 个 Boss/怪机制，
## 每个 case 一组参数（"矿晶甲虫：护甲减伤 30%，累计 300 伤害后碎裂"…）。
## 它是《怪物设计分册》第 4/5/6/9 章的**直接落地**，与 EnemyBase 的
## 战斗逻辑零耦合（只写字段、不做判定），却是该文件里最大的一块。
##
## 抽出来后：改一个怪的机制参数只开这一个文件，不必翻 2000 行的敌人基类。
##
## ## 这是**纯数据表**，不是行为
##
## 本函数只把参数写进 `e` 的字段，**不做任何判定、不产生副作用**。
## 行为（什么时候触发光环、突进怎么走、死亡放什么毒）在 enemy_base.gd 里，
## 因为它们需要读 `_player` / 位置 / 战斗状态。
##
## ## 为什么接收 `e` 而不是继承
##
## 机制字段（`aura_spec` / `summon_spec` / `death_zone`…）**必须留在 EnemyBase 上**——
## 测试直接读 `e.death_zone` / `e.summon_spec`（见 test_element_buff 的分册接线断言），
## 而且行为函数也用它们。故这里按鸭子类型写 `e.xxx`，
## 字段归属不变、player 与测试零改动。


## 按机制名装配参数。`key` 为空或未实现时静默返回（见文末 default 分支）。
##
## **逐字搬运自 enemy_base._apply_mechanic**，禁止归纳合并——
## 那张表一个 case 对应分册一条，合并即篡改。
static func apply(e, key: String) -> void:
	if key.is_empty():
		return
	e._base_atk = e.atk
	match key:
		# 9-1 混沌利刃：攻击附带真实伤害（无视护甲）
		"true_damage":
			e.true_damage = true
		# 2-14 矿晶甲虫：常驻护甲减伤 30%，累计受到 300 伤害后碎裂
		"armor_break":
			e.armor_plates = 0.30
			e.armor_break_at = 300.0
		# 8-26 虚无守卫：每受一次攻击伤害 +5%（最多 10 层）
		"rage_on_hit":
			e.rage_per_hit = 0.05
			e.rage_max_stacks = 10
		# 6-21 / 4.10 灰烬行者：攻击命中后进入灰烬形态（闪避+50%、移速+30%，4 秒）
		"ash_form":
			e.ash_chance_on_hit = 1.0
			e.ash_duration = 4.0
		# 8-25 时间畸变者：攻击后减速玩家 50%（3 秒），自身攻速 +30%（3 秒）
		"slow_haste":
			e.slow_target_pct = 0.50
			e.slow_target_seconds = 3.0
			e.haste_self_pct = 0.30
			e.haste_self_seconds = 3.0
		# 9-5 虚空吞噬者：击杀单位恢复 20% 血量并增大体型（伤害 +10%）。
		# 分册原文「每击杀一个单位（**包括其他怪物**）」——所以不能只认玩家击杀，
		# 得靠 `unit_died` 广播。参数字典见 `MonsterDB._special_for`。
		"devour_grow":
			e.devour_heal_pct = 0.20
			e.devour_atk_pct = 0.10
			e.devour_scale_pct = 0.10
			e._broadcast_death = true
		# 8-24 熵能浮体：攻击后标记玩家 6 秒
		"mark_player":
			e.hit_mark_seconds = 6.0
		# 4.7 石翼蝙蝠：命中击退玩家
		"knockback_on_hit":
			e.melee_knockback = 4.0
		# 4-16 毒腺蛙：攻击后留下毒液区（5 秒，每秒 15 伤），
		# 区域内**怪物**获得回血（每秒 +10）——分册原文如此，同区敌方也受益
		"poison_zone":
			e.zone_on_attack = {"radius": 2.5, "duration": 5.0, "damage": 15.0,
				"heal": 10.0, "friendly_group": "enemies",
				"color": Color(0.35, 0.85, 0.25, 0.45)}
		# 6-22 炎魔幼体：每 15 秒释放火焰光环（半径 4，每秒 40 伤，持续 4 秒）
		"flame_aura":
			e.aura_interval = 15.0
			e.aura_spec = {"radius": 4.0, "duration": 4.0, "damage": 40.0,
				"color": Color(1.0, 0.45, 0.1, 0.45)}
		# 4-18 沼泽巨人：每 10 秒释放范围水波（减速玩家 40%，4 秒）
		"water_pulse":
			e.aura_interval = 10.0
			e.aura_spec = {"radius": 5.0, "duration": 4.0, "damage": 0.0,
				"slow_buff": "mire", "color": Color(0.3, 0.6, 1.0, 0.4)}
		# 4.6 熔岩猎犬：突进时留下岩浆轨迹（持续伤害区域）
		"dash_lava_trail":
			e.trail_spec = {"radius": 1.2, "duration": 3.0, "damage": 12.0,
				"color": Color(1.0, 0.3, 0.1, 0.5)}
		# ——攻击/突进附加效果（分册 4.x / 5.x / 6.x）——
		# 4.4 骸骨弓手：被近身(≤5m)时射速翻倍 3 秒，每场战斗 1 次
		"haste_when_melee":
			e.melee_haste_range = 5.0
			e.melee_haste_mult = 2.0
			e.melee_haste_seconds = 3.0
		# 4.5 狂乱囚徒：低血量(≤30%)时攻击 +50%
		"enrage_low_hp":
			e.enrage_below_pct = 0.30
			e.enrage_atk_pct = 0.50
		# 4.5 狂怒恶魔：每次命中自身攻击 +5%（最多 8 层）
		"atk_stack_on_hit":
			e.hit_atk_pct = 0.05
			e.hit_atk_max = 8
		# 4.5 虚空狂战士：命中使玩家受治疗 -50%，6 秒
		"healcut_on_hit":
			e.hit_healcut_seconds = 6.0
		# 4.6 骸骨猎犬：突进后留减速陷阱（50%，3 秒）
		"dash_slow_trap":
			e.trap_slow_buff = "thorn_slow"
		# 4.6 狱卒猎犬：突进未命中后硬直 0.5 秒（分册原文「突进失败后硬直」）
		"dash_stun_self":
			e.dash_stun_seconds = 0.5
		# 4.6 虚空猎犬：突进距离翻倍，命中后定身 1.5 秒
		"dash_root":
			e.dash_range_mult = 2.0
			e.hit_root_seconds = 1.5
		# 4.7 墓穴蝙蝠：受击后分裂为 2 只小蝙蝠
		"split_on_hit":
			e.hit_split_count = 2
		# 4.7 硫磺蝙蝠：被命中后闪避 +40%，3 秒（每次受击刷新）
		"dodge_on_hit":
			e.hit_dodge_bonus = 0.40
			e.hit_dodge_seconds = 3.0
		# 4.8 硫磺幽魂：命中后减速玩家 40%，3 秒
		# **必须用有时效的词条**：thorn_slow 是 duration=0 的永久词条
		# （它靠「离开区域时移除」生效，见 DamageZone），
		# 拿来当命中减速会让玩家被永久 -50% 移速且无法解除。
		# mire 的 slow=0.40 / 3 秒 与这里的策划口径一致。
		"slow_on_hit":
			e.hit_slow_buff = "mire"
		# 4.9 墓穴巨鼠：每 10 秒恐惧吼叫（玩家移速 -30%，3 秒）
		"fear_roar":
			e.aura_interval = 10.0
			e.aura_spec = {"radius": 8.0, "duration": 3.0, "damage": 0.0,
				"slow_buff": "mire", "color": Color(0.5, 0.2, 0.6, 0.35)}
		# ——传送/位移 · 潜伏 · 护盾（分册 4.x / 5.x / 6.x）——
		# 9-4 熵能幽魂：命中后随机交换玩家与怪物位置（≤8 米）
		"swap_positions":
			e.hit_swap_positions = true
		# 4.8 熵能幽灵：射击后瞬移 3 米
		"blink_after_shot":
			e.teleport_after_shot = 3.0
		# 4.7 虚空蝠群：闪避成功后瞬移到玩家背后
		"teleport_behind":
			e.teleport_behind = true
		# 2-13 暗影潜伏者：常态隐身（半透明），攻击显形，受击显形 3 秒
		"stealth":
			e.stealth_always = true
		# 4.10 虚空魅影：闪避成功后隐身 3 秒，退出隐身时突袭 +50%
		"stealth_ambush":
			e.stealth_exit_bonus = 0.50
		# 4-17 湿地伏击者：潜伏于地面，玩家靠近 3 米内突袭（高伤害）
		"ambush":
			e.ambush = true
			e.ambush_range = 3.0
			e.ambush_damage_pct = 2.0
		# 6-20 熔炉核心：周期性全屏脉冲（每秒 15 伤，3 秒）期间自身无敌
		"pulse_invuln":
			e.aura_interval = 12.0
			e.aura_spec = {"radius": 12.0, "duration": 3.0, "damage": 15.0,
				"color": Color(1.0, 0.6, 0.2, 0.35)}
			e.pulse_invuln = true
		# 4.9 熔岩巨兽：每 8 秒熔岩光环（4 米，每秒 20 伤）；
		# 站熔岩地面每秒回 15 血（分册原文如此，同区敌方也受益——
		# 与 4-16 毒腺蛙的毒液区同一口径，不是笔误）。
		#
		# 「站熔岩地面回血」= 让光环跟随自身：怪物站在自己制造的光环里自然回血。
		# 这样不需要给引擎引入「熔岩地面」这个新概念，
		# 却与分册「站熔岩地面」的语义完全一致（光环就是它脚下那片熔岩）。
		"lava_aura":
			e.aura_interval = 8.0
			e.aura_spec = {"radius": 4.0, "duration": 4.0, "damage": 20.0,
				"heal": 15.0, "friendly_group": "enemies", "follow": true,
				"color": Color(1.0, 0.35, 0.05, 0.45)}
		# 9-3 扭曲巨兽：每 10 秒全屏引力（拉向自身，3 秒）
		"gravity_pull":
			e.aura_interval = 10.0
			e.gravity_pull = true
		# 4.9 虚空巨兽：每 6 秒虚空引力（牵引玩家 2 秒，期间每秒 30 伤）。
		# 与扭曲巨兽共用引力原语，多出的是「持续时长 + 期间伤害」。
		"void_gravity":
			e.aura_interval = 6.0
			e.gravity_pull = true
			e.gravity_pull_seconds = 2.0
			e.gravity_pull_dps = 30.0
		# 9-4 虚空猎手：突进距离翻倍，命中后定身 1.5 秒
		"long_dash_root":
			e.dash_range_mult = 2.0
			e.hit_root_seconds = 1.5
		# 9-8 暗影哨兵：每 20 秒生成护盾（吸收 200），期间免疫控制
		"shield_immune":
			e.shield_on_timer = 20.0
			e.shield_amount = 200.0
		# ——召唤 · 死亡变体 · 弹道变体（分册 4.x / 5.x）——
		# 4.3 符文哨兵：每 3 次射击后发射穿透箭
		"pierce_every_3":
			e.pierce_every = 3
		# 4.4 熔炉哨兵：射击点留下虚空回响（范围内减速 30%、每秒 15 伤）
		"shot_void_echo":
			e.void_echo = true
		# 4.10 虚空魅影：闪避成功后瞬移到玩家背后，下次攻击 +50%
		"dodge_teleport":
			e.dodge_teleport = true
			e._next_hit_bonus = 0.50
		# 4.10 迷雾幽灵：闪避成功后破除玩家闪避（命中必中）
		"dodge_break":
			e.dodge_break = true
		# ——死亡区域变体（分册 4.2 毒系四阶段递进，数值取原文）——
		# 机制名在 mech 字段；_special_for 只映射了 death_poison，
		# 故三个变体必须在**这里**按 mech 装配，读 special 是读不到的。
		"death_poison":
			e.death_zone = EnemyBase.DeathZone.POISON        # 毒瘴僵尸：基础毒雾
		"death_poison_big":
			e.death_zone = EnemyBase.DeathZone.BIG_POISON   # 腐毒僵尸：毒雾扩大
		"death_sulfur":
			e.death_zone = EnemyBase.DeathZone.SULFUR        # 硫磺僵尸：硫磺爆炸点燃地面
		"death_entropy":
			e.death_zone = EnemyBase.DeathZone.ENTROPY       # 熵毒僵尸：熵毒领域
		# ——召唤变体（分册 4.1）——
		# special.summon.id 是 "forge_imp"/"void_rift"，**不在 MonsterDB 里**，
		# 直接查表会得到空字典 → 召唤不出东西。这里补内联数值并区分形态。
		"summon_imp":
			e.summon_spec = {"id": "forge_imp", "name": "熔炉小鬼",
				"hp": 100.0, "atk": 20.0, "count": 2,
				"death_explode": true, "explode_damage": 30.0, "chance": 1.0}
		"summon_rift":
			# 虚空僵尸：召唤虚空裂痕——不是小怪，是一块持续 6 秒的伤害区域
			e.summon_spec = {"zone": true, "radius": 2.5, "duration": 6.0,
				"damage": 40.0, "count": 1, "chance": 1.0}
		# 4.5 熔炉哨兵（p3）的射击火焰区已由 shot_fire_zone 处理；
		# 虚空哨卫（p4）的虚空回响：射击点留减速+伤害区域
		"shot_void_echo":
			e.void_echo = true
		_:
			pass   # 其余机制尚未实现（见 docs/progress 待办）
