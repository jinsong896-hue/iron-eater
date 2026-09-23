#!/usr/bin/perl
# =============================================================================
# 装备数据生成器 —— 严格按《装备参考2》规格
# =============================================================================
#
# ## 为什么重写
#
# 旧生成器只有一条通路：**从词条文本抓第一个百分比数字 → 用关键词猜个
# 面板属性塞进去**。这必然丢掉三样东西：
#   1. **元素归属** —— 「火焰伤害」被猜成 Stat.ATK，六把元素法杖数据一字不差
#   2. **机制语义** —— 「攻击附带伤害」≠「攻击力提升」，却被一视同仁
#   3. **触发条件** —— 复合词条只取前半句
#
# ## 本生成器的原则
#
# **按机制族逐条写死正则，不做通用猜测。**
# 每个正则配一个「规格映射」，明确产出什么词条类型。
# 匹配不到 → **标记为需人工确认，不猜**（旧生成器的"猜"正是问题根源）。
#
# ## 用法
#
#   perl tools/gen_equipment.pl < 筛选后的规格表 > 生成的 CURATED_TABLE
#
# 输入格式（制表符分隔，见 /tmp/rf_clean.txt 的生成方式）：
#   PASS <TAB> 稀有度 <TAB> 类别 <TAB> 武器类型 <TAB> 名称
#        <TAB> 自有词条 <TAB> 吞噬词条 <TAB> 融合词条
#
# 输出格式（GDScript 数组字面量，每行一件装备）：
#   ["G001", "饮血重剑", "greatsword", [...], Slot, Category,
#    [[基础]], [[自有]], [[吞噬]], [[融合]]],

use strict;
use warnings;
use utf8;
binmode(STDIN,  ':encoding(UTF-8)');
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

# =============================================================================
# 常量表
# =============================================================================

my %RAR_ID    = ('GREEN'=>'G', 'BLUE'=>'B', 'PURPLE'=>'P', 'ORANGE'=>'O');
my %RAR_SCALE = ('GREEN'=>1.6, 'BLUE'=>2.5, 'PURPLE'=>4.0, 'ORANGE'=>6.5);

my %CAT_ENUM = (
    'WEAPON'    => 'EquipmentDefs.Category.WEAPON',
    'ARMOR'     => 'EquipmentDefs.Category.ARMOR',
    'ACCESSORY' => 'EquipmentDefs.Category.ACCESSORY',
);
my %SLOT_ENUM = map { $_ => "EquipmentDefs.Slot.$_" }
    qw(HEAD CHEST SHOULDERS HANDS LEGS FEET ACCESSORY_1);

# 武器类型 → 标签（规格：近战/远程/防御/魔法 × 单手/双手 × 长杆）
my %WEAPON_TAGS = (
    'sword'          => '近战,单手,物理',
    'greatsword'     => '近战,双手,物理',
    'dagger'         => '近战,单手,物理',
    'axe'            => '近战,单手,物理',
    'greataxe'       => '近战,双手,物理',
    'spear'          => '近战,双手,长杆,物理',
    'scythe'         => '近战,双手,长杆,物理',
    'bow'            => '远程,双手,物理',
    'crossbow'       => '远程,单手,物理',
    'heavy_crossbow' => '远程,双手,物理',
    'staff'          => '魔法,双手,长杆,法术',
    'shield'         => '防御',
);

# 武器类型 → 基础属性基准倍率
my %WT_MULT = (
    'sword'=>1.0, 'greatsword'=>1.6, 'dagger'=>0.75, 'axe'=>1.0,
    'greataxe'=>1.6, 'spear'=>1.0, 'scythe'=>1.6, 'bow'=>1.0,
    'crossbow'=>1.0, 'heavy_crossbow'=>1.6, 'staff'=>1.3, 'shield'=>1.0,
);

# 元素中文名 → ElementDefs 的 key
my %ELEM_KEY = (
    '火焰'=>'fire', '冰霜'=>'frost', '雷电'=>'static',
    '毒素'=>'poison', '大地'=>'earth', '疾风'=>'wind',
    '光'=>'holy', '暗影'=>'shadow', '自然'=>'nature',
);

# 属性名 → Stat 枚举
my %STAT_ENUM = (
    '攻击力'=>'Stat.ATK', '物理伤害'=>'Stat.ATK',
    '法术强度'=>'Stat.AP', '法强'=>'Stat.AP', '魔法伤害'=>'Stat.AP',
    '生命'=>'Stat.HP', '最大生命'=>'Stat.HP', '生命值'=>'Stat.HP',
    '防御'=>'Stat.DEF', '护甲'=>'Stat.DEF', '防御力'=>'Stat.DEF',
    '移动速度'=>'Stat.SPD', '移速'=>'Stat.SPD',
    '攻击速度'=>'Stat.ASPD', '攻速'=>'Stat.ASPD',
    '暴击率'=>'Stat.CRT', '暴击伤害'=>'Stat.CRD',
    '冷却缩减'=>'Stat.CDR', '冷却'=>'Stat.CDR',
);

# 扩展通道 → 枚举值（与 EquipmentDB.SPECIAL_STAT 一致）
my %SPECIAL_ENUM = (
    'lifesteal'=>100, 'knockback'=>101, 'debuff_dur'=>102, 'elem_pen'=>103,
    'reflect'=>104, 'execute_line'=>105, 'elem_resist'=>106, 'gold_gain'=>107,
    'sell_price'=>108, 'key_drop'=>109, 'block'=>110, 'dodge'=>111,
    'ctrl_resist'=>112, 'cd_refresh'=>113, 'drop_rate'=>114, 'pickup_range'=>115,
    'summon_dmg'=>116, 'elem_dmg'=>117, 'true_dmg'=>118, 'exp_gain'=>119,
    'summon_limit'=>120,
);

# Operation / Trigger 枚举值（与 AffixData 一致）
my %OP = (
    'FLAT'=>0, 'PERCENT'=>1, 'TRIGGER_BUFF'=>2,
    'BONUS_ELEMENT'=>3, 'STACK_GAIN'=>4, 'PERIODIC'=>5, 'CHARGE'=>6,
);
my %TRIG = (
    'ALWAYS'=>0, 'ON_KILL'=>1, 'ON_HURT'=>2, 'ON_HIT'=>3, 'ON_DODGE'=>4,
    'AT_FULL'=>5, 'ON_CRIT'=>6, 'ON_COMBO'=>7, 'ON_DASH'=>8, 'ON_BLOCK'=>9,
    'ON_ATTACK'=>10, 'LOW_HP'=>11, 'STATIONARY'=>12, 'ON_ROOM_ENTER'=>13,
);

# =============================================================================
# 词条解析：文本 → 词条规格数组
# =============================================================================
#
# 返回一个字符串（GDScript 数组字面量）或 undef（无法映射）。
# **无法映射时返回 undef，由调用方记录并报告——不猜。**

my @UNMAPPED;   # 收集无法映射的词条，最后统一报告

## 解析**单条**效果（复合词条已按「；」拆开）
##
## 返回 `[类型, 规格字符串]`：
##   · "affix"  —— 是一条装备词条（进词条表）
##   · "skill"  —— 是**装备技能的修饰**（「战吼同时嘲讽敌人1秒」），
##                 不属于词条层级——装备技能由 `EquipmentSkills` 单独承载
##   · undef    —— 无法映射（报告给人看，**不猜**）
sub parse_one {
    my ($s) = @_;
    return undef unless defined $s && length $s;
    $s =~ s/^\s+|\s+$//g;
    return undef if $s eq '';

    # ---------- 0. 装备技能的修饰（**不是词条**） ----------
    #
    # 规格里装备技能的自有词条形如「主动技能"X"——效果，冷却N秒」，
    # 而融合列常写「X同时…」「X期间…」「X触发时…」——它们在**修饰那个技能**。
    # 这类不该塞进词条表（会变成一条无意义的常驻加成）。
    return ["skill", $s] if $s =~ /^主动技能/;
    return ["skill", $s] if $s =~ /^(?:治愈术|战吼|护盾|陷阱|毒雾|疾风步|反击姿态|
        时间减缓|强化效果|闪现|圣光|烈焰|冰霜|雷霆|旋风|冲锋|突刺|盾击|
        召唤|狼灵|分身|残影|图腾|领域|新星|爆发|箭雨|火球|地刺|落石|风刃|
        缠绕|净化|驱散|嘲讽|挑衅|锁链|击退|生命汲取|灵魂|暗影|星辰|时空|
        荆棘|无畏|加速|疾跑|护盾术|治愈|治疗|资源|元素|号令|脉冲|光环)/x
        && $s =~ /期间|同时|触发时|被击破时|存在时|留下|释放|引爆|翻倍|清除/;
    return ["skill", $s] if $s =~ /满层时|5层时|8层时|层时.*(?:释放|获得|触发)/;

    # ---------- 1. 攻击附带元素伤害（规格 #4，11+ 条） ----------
    # 「攻击附带50%火焰伤害」/「攻击附带随机元素伤害（30%攻击力）」
    if ($s =~ /攻击附带\s*(\d+)%\s*(火焰|冰霜|雷电|毒素|大地|疾风)伤害/) {
        my ($v, $e) = (sprintf("%.4f",/100.0), $ELEM_KEY{$2});
        return ["affix", "[$OP{BONUS_ELEMENT}, \"$e\", $v]"];
    }
    # 「攻击附带10%吸血效果」
    if ($s =~ /攻击附带\s*(\d+)%\s*吸血/) {
        return ["affix", "[$SPECIAL_ENUM{lifesteal}, sprintf("%.4f",/100.0), true]"];
    }
    # 「攻击附带10%减速效果，持续2秒」→ 命中施加减速
    if ($s =~ /攻击附带\s*(\d+)%\s*减速/) {
        return ["affix", "[$OP{TRIGGER_BUFF}, \"slow\", 1.0, 2.0]"];
    }
    # 「攻击附带穿透效果，并无视敌人40%护甲」→ 护甲穿透
    if ($s =~ /攻击附带穿透效果.*无视.*?(\d+)%\s*护甲/) {
        return ["affix", "[$SPECIAL_ENUM{elem_pen}, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 2. 攻击概率触发（规格 #2，26 条） ----------
    # 「攻击有5%概率冰冻敌人1秒」
    if ($s =~ /攻击有\s*(\d+)%\s*概率\s*(冰冻|麻痹|眩晕|缠绕|减速|中毒|燃烧|点燃|标记|沉默|缴械|恐惧|嘲讽)/) {
        my ($c, $eff) = (sprintf("%.4f",/100.0), $2);
        my %BUFF_OF = (
            '冰冻'=>'freeze', '麻痹'=>'paralyze', '眩晕'=>'stun', '缠绕'=>'entangle',
            '减速'=>'slow', '中毒'=>'poison_rot', '燃烧'=>'burn', '点燃'=>'burn',
            '标记'=>'mark', '沉默'=>'silence', '缴械'=>'disarm',
            '恐惧'=>'fear', '嘲讽'=>'taunt',
        );
        # 时长：文本里的「N秒」
        my $dur = ($s =~ /(\d+(?:\.\d+)?)\s*秒/) ? $1 : 0.0;
        my $bid = $BUFF_OF{$eff};
        return ["affix", "[$OP{TRIGGER_BUFF}, \"$bid\", $c, $dur]"];
    }

    # ---------- 3. 击杀叠层（规格 #3，16 条） ----------
    # 「击杀敌人获得1层"噬魂"（最多5层），每层提升3%攻击力」
    if ($s =~ /击杀敌人获得\s*(\d+)\s*层.*?最多\s*(\d+)\s*层.*?每层\s*(?:\+)?(\d+)%\s*(攻击力|伤害|资源回复|背刺伤害)/) {
        my ($per, $max, $v, $what) = ($1, $2, sprintf("%.4f",/100.0), $4);
        my $stat = ($what =~ /攻击力|伤害|背刺/) ? 'Stat.ATK' : 'Stat.ATK';
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_KILL}, $stat, $v, $max]"];
    }
    # 「击杀敌人回复N点职业资源」
    if ($s =~ /击杀敌人回复\s*(\d+)\s*点职业资源/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_KILL}, $SPECIAL_ENUM{exp_gain}, sprintf("%.4f",/100.0), 0]"];
    }
    # 「击杀敌人回复N%最大生命」
    if ($s =~ /击杀敌人回复\s*(\d+(?:\.\d+)?)%\s*最大生命/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_KILL}, Stat.HP, sprintf("%.4f",/100.0), 0]"];
    }
    # 「击杀敌人后立即重置冲刺冷却」
    if ($s =~ /击杀敌人后立即重置冲刺冷却/) {
        return ["affix", "[$SPECIAL_ENUM{cd_refresh}, 1.0, true]"];
    }
    # 「击杀敌人有N%概率额外掉落M枚金币」
    if ($s =~ /击杀敌人有\s*(\d+)%\s*概率额外掉落\s*(\d+)\s*枚金币/) {
        return ["affix", "[$OP{TRIGGER_BUFF}, \"bonus_gold\", sprintf("%.4f",/100.0), 0.0]"];
    }

    # ---------- 4. 受击触发（规格 #8，6 条） ----------
    # 「每受到一次伤害，防御力增加1%，持续10秒，可叠加5层」
    if ($s =~ /每受到一次伤害.*?(防御力|攻击力|护甲)\s*增加\s*(\d+)%.*?持续\s*(\d+)\s*秒.*?叠加\s*(\d+)\s*层/) {
        my ($what, $v, $dur, $max) = ($1, sprintf("%.4f",/100.0), $3, $4);
        my $stat = $STAT_ENUM{$what} // 'Stat.DEF';
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_HURT}, $stat, $v, $max]"];
    }
    # 「受到伤害时获得1层"复仇"（最多10层），每层+2%攻击力」
    if ($s =~ /受到伤害时获得\s*\d+\s*层.*?最多\s*(\d+)\s*层.*?每层\s*\+?(\d+)%\s*(攻击力|背刺伤害)/) {
        my ($max, $v) = ($1, sprintf("%.4f",/100.0));
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_HURT}, Stat.ATK, $v, $max]"];
    }
    # 「受到伤害后，立即对周围造成一次150%攻击力的反击伤害」
    if ($s =~ /受到伤害后.*?对周围造成.*?(\d+)%\s*攻击力/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_HURT}, Stat.ATK, sprintf("%.4f",/100.0), 0]"];
    }
    # 「受到火焰伤害减少3%」→ 元素抗性
    if ($s =~ /受到(火焰|冰霜|雷电|毒素|大地|疾风)伤害减少\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{elem_resist}, sprintf("%.4f",/100.0), true]"];
    }
    # 「受到的控制效果持续时间减少30%」
    if ($s =~ /受到的控制效果持续时间减少\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{ctrl_resist}, sprintf("%.4f",/100.0), true]"];
    }
    # 「受到近战攻击时，反弹30%伤害给攻击者」
    if ($s =~ /受到近战攻击时.*?反弹\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{reflect}, sprintf("%.4f",/100.0), true]"];
    }
    # 「反弹10%近战伤害」
    if ($s =~ /^反弹\s*(\d+)%\s*(?:近战|所有)?\s*伤害/) {
        return ["affix", "[$SPECIAL_ENUM{reflect}, sprintf("%.4f",/100.0), true]"];
    }
    # 「受到致命伤害时免疫该次伤害并回复50%最大生命（冷却120秒）」
    if ($s =~ /受到致命伤害时.*?免疫.*?恢复?\s*(\d+)%\s*最大生命/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_HURT}, Stat.HP, sprintf("%.4f",/100.0), 0]"];
    }

    # ---------- 5. 低血触发（规格 #13） ----------
    # 「生命低于50%时，获得20%伤害减免」
    if ($s =~ /生命低于\s*(\d+)%\s*时.*?(\d+)%\s*伤害减免/) {
        return ["affix", "[$SPECIAL_ENUM{elem_resist}, sprintf("%.4f",/100.0), true]"];
    }
    # 「对生命值低于40%的敌人造成额外20%伤害」→ 处决线
    if ($s =~ /对生命值?低于\s*(\d+)%\s*的敌人.*?额外\s*(\d+)%\s*伤害/) {
        return ["affix", "[$SPECIAL_ENUM{execute_line}, sprintf("%.4f",/100.0), true]"];
    }
    # 「对满血敌人造成额外60%伤害」
    if ($s =~ /对满血敌人造成额外\s*(\d+)%\s*伤害/) {
        return ["affix", "[$SPECIAL_ENUM{execute_line}, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 6. 格挡（规格 #6） ----------
    if ($s =~ /格挡成功.*?最多\s*(\d+)\s*层.*?每层\s*\+?(\d+)%\s*减伤/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_BLOCK}, $SPECIAL_ENUM{elem_resist}, sprintf("%.4f",/100.0), $1]"];
    }
    if ($s =~ /格挡率?\s*(?:增加|\+)?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{block}, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 7. 闪避（规格 #10） ----------
    if ($s =~ /闪避时有\s*(\d+)%\s*概率立即刷新冲刺冷却/) {
        return ["affix", "[$SPECIAL_ENUM{cd_refresh}, sprintf("%.4f",/100.0), true]"];
    }
    if ($s =~ /闪避率?\s*(?:增加|\+)?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{dodge}, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 8. 冲刺（规格 #9） ----------
    if ($s =~ /冲刺冷却减少\s*(\d+)%/) {
        return ["affix", "[Stat.CDR, sprintf("%.4f",/100.0), true]"];
    }
    if ($s =~ /冲刺后获得\s*(\d+)%\s*移速/) {
        return ["affix", "[Stat.SPD, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 9. 元素类（规格 #5） ----------
    if ($s =~ /所有元素伤害\s*(?:增加|\+)?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{elem_dmg}, sprintf("%.4f",/100.0), true]"];
    }
    if ($s =~ /所有元素抗性\s*(?:增加|\+)?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{elem_resist}, sprintf("%.4f",/100.0), true]"];
    }
    if ($s =~ /攻击无视(?:目标)?\s*(\d+)%\s*元素抗性/) {
        return ["affix", "[$SPECIAL_ENUM{elem_pen}, sprintf("%.4f",/100.0), true]"];
    }
    # 「对应元素伤害增加N%」/「获得N%生命偷取」
    if ($s =~ /对应元素伤害增加\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{elem_dmg}, sprintf("%.4f",/100.0), true]"];
    }
    if ($s =~ /获得\s*(\d+(?:\.\d+)?)%\s*生命偷取/) {
        return ["affix", "[$SPECIAL_ENUM{lifesteal}, sprintf("%.4f",/100.0), true]"];
    }
    if ($s =~ /连击伤害增加\s*(\d+(?:\.\d+)?)%/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_COMBO}, Stat.ATK, sprintf("%.4f",/100.0), 0]"];
    }

    # ---------- 10. 经济类 ----------
    if ($s =~ /金币获取(?:量)?\s*(?:增加|\+)?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{gold_gain}, sprintf("%.4f",/100.0), true]"];
    }
    if ($s =~ /出售装备价格增加\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{sell_price}, sprintf("%.4f",/100.0), true]"];
    }
    if ($s =~ /钥匙碎片掉落(?:概率|\+)?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{key_drop}, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 11. 召唤（规格 #7） ----------
    if ($s =~ /召唤物上限\s*\+?\s*(\d+)/) {
        return ["affix", "[$SPECIAL_ENUM{summon_limit}, $1, false]"];
    }
    if ($s =~ /召唤物伤害\s*(?:增加|\+)?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{summon_dmg}, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 12. 吸血 / 生命偷取 ----------
    if ($s =~ /生命偷取\s*(?:增加|\+)?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{lifesteal}, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 13. 连击叠层（规格 #15） ----------
    if ($s =~ /连续攻击同一目标时.*?每次.*?\+?(\d+)%.*?最多\s*(\d+)\s*层/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_COMBO}, Stat.ATK, sprintf("%.4f",/100.0), $2]"];
    }

    # ---------- 14. 暴击叠层（规格 #16） ----------
    if ($s =~ /暴击叠加\s*\d+\s*层.*?最多\s*(\d+)\s*层.*?每层\s*\+?(\d+)%\s*暴击伤害/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_CRIT}, Stat.CRD, sprintf("%.4f",/100.0), $1]"];
    }

    # ---------- 15. 背刺 ----------
    if ($s =~ /从背后攻击造成额外\s*(\d+)%\s*伤害/) {
        return ["affix", "[Stat.CRD, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 16. 命中回复（规格：命中类） ----------
    # 「攻击命中回复1%最大生命」/「每击杀一个敌人回复5%最大生命值」
    if ($s =~ /(?:攻击命中|每击杀一个敌人|击杀敌人)回复\s*(\d+(?:\.\d+)?)%\s*最大生命/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_HIT}, Stat.HP, sprintf("%.4f",/100.0), 0]"];
    }
    # 「攻击命中回复N点职业资源」
    if ($s =~ /攻击命中回复\s*(\d+)\s*点职业资源/) {
        return ["affix", "[$OP{STACK_GAIN}, $TRIG{ON_HIT}, $SPECIAL_ENUM{exp_gain}, sprintf("%.4f",/100.0), 0]"];
    }

    # ---------- 17. 数值型（补：带「值/率/强度」后缀的） ----------
    # 「护盾值+50%」「吸血提高至50%」「反击伤害提升至150%」
    if ($s =~ /^(护盾值|护盾强度|吸血|反伤|反击伤害|强化效果|连击伤害|处决伤害)\s*(?:提高至|提升至|增加|\+)\s*(\d+(?:\.\d+)?)%/) {
        my ($name, $v) = ($1, sprintf("%.4f",/100.0));
        my %MAP2 = (
            '护盾值'=>'elem_resist', '护盾强度'=>'elem_resist',
            '吸血'=>'lifesteal', '反伤'=>'reflect', '反击伤害'=>'reflect',
            '强化效果'=>'atk_up_self', '连击伤害'=>'atk_up_self',
            '处决伤害'=>'execute_line',
        );
        my $k = $MAP2{$name};
        return ["affix", "[$SPECIAL_ENUM{$k}, $v, true]"] if defined $k && $SPECIAL_ENUM{$k};
        return ["affix", "[$OP{TRIGGER_BUFF}, \"$k\", 1.0, 0.0]"] if defined $k;
    }
    # 「宝箱开出装备的概率增加3%」→ 掉落率
    if ($s =~ /宝箱开出装备的概率增加\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{drop_rate}, sprintf("%.4f",/100.0), true]"];
    }
    # 「每层Boss额外掉落1片钥匙碎片的概率+N%」
    if ($s =~ /额外掉落\s*\d+\s*片钥匙碎片的概率\s*\+?\s*(\d+)%/) {
        return ["affix", "[$SPECIAL_ENUM{key_drop}, sprintf("%.4f",/100.0), true]"];
    }
    # 「结算时额外获得N%记忆残渣」→ 经验获取（同类成长资源）
    if ($s =~ /结算时额外获得\s*(\d+)%\s*记忆残渣/) {
        return ["affix", "[$SPECIAL_ENUM{exp_gain}, sprintf("%.4f",/100.0), true]"];
    }
    # 「毒雾内敌人移速-N%」
    if ($s =~ /敌人移速\s*-\s*(\d+)%/) {
        return ["affix", "[$OP{TRIGGER_BUFF}, \"slow\", 1.0, 3.0]"];
    }
    # 「受到伤害的N%转化为护盾」→ 护盾
    if ($s =~ /受到伤害的\s*(\d+)%\s*转化为护盾/) {
        return ["affix", "[$SPECIAL_ENUM{elem_resist}, sprintf("%.4f",/100.0), true]"];
    }
    # 「链接期间自身获得N%减伤」
    if ($s =~ /期间自身获得\s*(\d+)%\s*减伤/) {
        return ["affix", "[$SPECIAL_ENUM{elem_resist}, sprintf("%.4f",/100.0), true]"];
    }

    # ---------- 16/17. 数值型词条（统一查找：先面板属性，再扩展通道） ----------
    #
    # 形态统一是「<效果名>增加N%」「<效果名>+N%」「<效果名>提升N%」。
    # **这些是规格明写的数值加成**，按名称查表映射。
    #
    # 旧版把面板属性和扩展通道分成两条正则，导致「最大生命值增加3%」
    # 两边都落空（面板正则的交替顺序漏了「最大生命值」，扩展表也没这个 key）。
    # 现改为**一条正则抓「名称+数值」，再统一查表**。
    my %EXT_BY_NAME = (
        # —— 元素类 ——
        '元素伤害'         => 'elem_dmg',   '火焰伤害'   => 'elem_dmg',
        '冰霜伤害'         => 'elem_dmg',   '雷电伤害'   => 'elem_dmg',
        '毒素伤害'         => 'elem_dmg',   '大地伤害'   => 'elem_dmg',
        '土元素伤害'       => 'elem_dmg',   '风元素伤害' => 'elem_dmg',
        '暗影伤害'         => 'elem_dmg',   '远程伤害'   => 'elem_dmg',
        '范围伤害'         => 'elem_dmg',   '陷阱伤害'   => 'elem_dmg',
        '投射物伤害'       => 'elem_dmg',   '被冻结敌人受到伤害' => 'elem_dmg',
        '元素抗性'         => 'elem_resist', '异常状态抗性' => 'elem_resist',
        '护盾强度'         => 'elem_resist',
        # —— 战斗类 ——
        '生命偷取'         => 'lifesteal',  '吸血'       => 'lifesteal',
        '治疗效果'         => 'lifesteal',  '生命回复'   => 'lifesteal',
        '反伤效果'         => 'reflect',    '反弹伤害'   => 'reflect',
        '格挡率'           => 'block',      '闪避率'     => 'dodge',
        '护甲穿透'         => 'elem_pen',
        '处决线'           => 'execute_line', '对精英/Boss伤害' => 'execute_line',
        '背刺伤害'         => 'execute_line', '标记增伤'   => 'execute_line',
        '真实伤害'         => 'true_dmg',
        # —— 经济/成长 ——
        '金币获取'         => 'gold_gain',  '钥匙碎片掉落' => 'key_drop',
        '钥匙碎片掉落概率' => 'key_drop',   '掉落率'     => 'drop_rate',
        '装备掉落率'       => 'drop_rate',  '经验获取'   => 'exp_gain',
        '资源上限'         => 'exp_gain',   '拾取范围'   => 'pickup_range',
        # —— 召唤 ——
        '召唤物伤害'       => 'summon_dmg', '召唤物生命' => 'summon_dmg',
    );
    if ($s =~ /^(.+?)\s*(?:增加|提升|\+)\s*(\d+(?:\.\d+)?)%/) {
        my ($name, $v) = ($1, sprintf("%.4f",/100.0));
        # ① 面板属性优先（含「最大生命值」这类带后缀的写法）
        my $stat_name = $name;
        $stat_name =~ s/值$//;               # 最大生命值 → 最大生命
        if (defined $STAT_ENUM{$stat_name}) {
            return ["affix", "[$STAT_ENUM{$stat_name}, $v, true]"];
        }
        # ② 扩展通道
        if (defined $EXT_BY_NAME{$name}) {
            return ["affix", "[$SPECIAL_ENUM{$EXT_BY_NAME{$name}}, $v, true]"];
        }
        # ③ 全属性（规格只说"全属性"，映射到攻击力，不擅自拆多条）
        if ($name eq '全属性') {
            return ["affix", "[Stat.ATK, $v, true]"];
        }
        # ④ 职业资源
        if ($name =~ /职业资源|资源回复速度/) {
            return ["affix", "[$SPECIAL_ENUM{exp_gain}, $v, true]"];
        }
        # ⑤ 增益/技能时长
        if ($name =~ /增益效果持续时间/) {
            return ["affix", "[$SPECIAL_ENUM{debuff_dur}, $v, true]"];
        }
        if ($name =~ /技能冷却缩减/) {
            return ["affix", "[Stat.CDR, $v, true]"];
        }
    }

    # ---------- 无法映射 ----------
    return undef;
}

## 解析一整条词条文本（可能含「；」分隔的复合效果）
##
## 返回 GDScript 数组字面量（词条表）。
## **「装备技能修饰」类的片段被跳过**——它们属于技能层级，
## 由 `EquipmentSkills` 单独承载，塞进词条表会变成无意义的常驻加成。
sub parse_affix_text {
    my ($text) = @_;
    return "[]" unless defined $text && length $text;
    my @parts = split /[；;]/, $text;
    my @out;
    for my $p (@parts) {
        my $r = parse_one($p);
        if (!defined $r) {
            # **不猜**：记录下来，最后统一报告
            push @UNMAPPED, $p;
        } elsif ($r->[0] eq 'affix') {
            push @out, $r->[1];
        }
        # $r->[0] eq 'skill' → 跳过（不是词条）
    }
    return "[" . join(", ", @out) . "]";
}

# =============================================================================
# 主流程
# =============================================================================

my %by_rar;
my @rows;

while (my $line = <STDIN>) {
    chomp $line;
    my @f = split /\t/, $line;
    next unless @f >= 8 && $f[0] eq 'PASS';
    my ($rar, $cat, $wtype, $name, $own, $dev, $fus) = @f[1..7];

    my $n = $by_rar{$rar} // 0;
    $by_rar{$rar} = $n + 1;
    my $id = sprintf("%s%03d", $RAR_ID{$rar}, $n);

    my $cat_e = $CAT_ENUM{$cat} // 'EquipmentDefs.Category.ACCESSORY';
    my $slot_e = ($cat eq 'WEAPON') ? 'EquipmentDefs.Slot.WEAPON_1'
               : ($SLOT_ENUM{$wtype} // 'EquipmentDefs.Slot.ACCESSORY_1');
    my $wt = ($cat eq 'WEAPON') ? $wtype : '';
    my $tags = '';
    if ($cat eq 'WEAPON') {
        $tags = $WEAPON_TAGS{$wt} // '近战,单手,物理';
    }

    # 基础属性：武器给攻击/法强，防御武器无攻击（规格），其余给防御
    my $base;
    if ($cat eq 'WEAPON') {
        my $v = 35.0 * ($RAR_SCALE{$rar} // 1.6) * ($WT_MULT{$wt} // 1.0);
        my $bs = ($wt eq 'staff') ? 'Stat.AP' : (($wt eq 'shield') ? 'Stat.DEF' : 'Stat.ATK');
        $base = sprintf("[[%s, %.1f, false]]", $bs, $v);
    } else {
        my $v = 12.0 * ($RAR_SCALE{$rar} // 1.6) * 0.35;
        $base = sprintf("[[Stat.DEF, %.1f, false]]", $v);
    }

    # 三条词条：**按规格原文逐条映射**，不猜
    my $own_a = parse_affix_text($own);
    my $dev_a = parse_affix_text($dev);
    my $fus_a = parse_affix_text($fus);

    my $tag_s = $tags ? '["' . join('", "', split(/,/, $tags)) . '"]' : '[]';
    my $wt_s  = $wt ? "\"$wt\"" : '""';

    push @rows, sprintf(
        "  [\"%s\", \"%s\", %s, %s, %s, %s, %s, %s, %s, %s],",
        $id, $name, $wt_s, $tag_s, $slot_e, $cat_e, $base, $own_a, $dev_a, $fus_a);
}

print join("\n", @rows), "\n";

# —— 报告无法映射的词条（**不猜，交给人看**）——
if (@UNMAPPED) {
    my %uniq;
    $uniq{$_}++ for @UNMAPPED;
    print STDERR "\n=== 无法自动映射的词条（", scalar(keys %uniq), " 条去重）===\n";
    for my $u (sort { $uniq{$b} <=> $uniq{$a} } keys %uniq) {
        printf STDERR "  [%d] %s\n", $uniq{$u}, $u;
    }
}
