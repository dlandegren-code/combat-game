---
name: parry-dodge-system
overview: >-
  Add Parry and Dodge defensive skills with attack vs defense rolls, fighting
  stance, weapon durability, and time-unit cost for defense.
createdAt: '2026-06-04T08:50:40.629Z'
todos:
  - id: add-exports
    content: >-
      Add attack_skill, parry_skill, dodge_skill, has_weapon, weapon_durability,
      defensive_option exports to player.gd and enemy.gd
    status: completed
  - id: defense-logic
    content: >-
      Rewrite take_damage to accept attacker_skill, run defense check, charge
      defender 1 time unit
    status: completed
  - id: attack-sites
    content: Update attack call sites in player.gd and enemy.gd to pass attack_skill
    status: completed
  - id: combat-manager-cost
    content: Add charge_defense_cost method to combat_manager.gd
    status: completed
  - id: health-bar
    content: Update health bars to show weapon durability and defensive stance
    status: completed
  - id: verify
    content: 'runAndVerify: clean compile, parry/dodge working in combat'
    status: completed
---
## Defense System

### Defense check formula
- Attack roll: `attack_skill + randi_range(1, 5)`
- Defense roll: `(parry_skill or dodge_skill) + randi_range(1, 5)`
- If defense >= attack: defense succeeds, 0 damage
- If defense < attack: defense fails, damage applied normally

### Parry specifics
- Requires `has_weapon == true`
- On success: `weapon_durability -= 1`
- If durability hits 0: weapon breaks, can no longer parry
- Can still dodge if weapon breaks (swap stance)

### Dodge specifics
- Always available (no equipment requirement)
- Higher variance: dodge_skill tends to be higher than parry_skill

### Time cost
- Defense attempt costs 1 time unit
- Charged to defender's `next_turn_at` via combat manager

### Fighting Stance
- `@export_enum("Parry", "Dodge") var defensive_option: int`
- 0 = Parry, 1 = Dodge
- Future: full stance resource with bonuses

### Defaults
- Hero: attack 5, parry 4, dodge 5, weapon dur 10, stance Parry
- Archer: attack 4, parry 2, dodge 7, weapon dur 8, stance Dodge
- Goblin: attack 3, parry 1, dodge 3, no weapon, stance Dodge
