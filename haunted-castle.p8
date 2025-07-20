pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- global constants
player_knife = {
	sprite = 32,
	length = 4,
	breadth = 4,
	h_sprite = 38,
	v_sprite = 54
}

player_sword = {
	sprite = 48,
	length = 8,
	breadth = 4,
	h_sprite = 7,
	v_sprite = 23
}

-- global state
debug_msg = nil
weapon = player_sword
spell = nil
spell_cnt = 1
room = nil
room_id = 601
blue_key = false
green_key = false
red_key = false
state = "playing"

function _init()
	rooms[room_id]()
end

function _update()
	if state == "playing" then
		entity_system()
		hurtbox_system()
		switch_system()
		trigger_system()
		exit_system()

		if not room.entities[0] then
			state = "gameover"
		end

		return
	end

	if state == "gameover" then
		if btn(5) then
			rooms[room_id]()
			state = "playing"
		end
	end

	if state == "found_weapon" then
		if btn(5) then
			state = "playing"
		end
	end

	if state == "found_spell" then
		if btn(5) then
			state = "playing"
		end
	end
end

function _draw()
	cls()
	map()

	for _, e in pairs(room.entities) do
		draw_sprite(e)
	end

	for _, h in pairs(room.hurtboxes) do
		draw_sprite(h)
	end

	-- draw room name
	local x = room.tx * 8
	local y = (room.ty - 2) * 8
	print("room:", x, y, 7)
	print(room.name, x, y + 8)

	print("weapon:", x + 48, y)
	if weapon then
		spr(weapon.sprite, x + 48, y + 6)
	else
		print("none", x + 48, y + 8)
	end

	if room.name == "library"
			and not spell then
		print("book:", x + 96, y)
		if room.book then
			spr(room.book, x + 96, y + 6)
		end
	else
		print("spell:", x + 96, y)
		if spell then
			spr(16, x + 96, y + 6)
			print("x" .. spell_cnt, x + 106, y + 8, 7)
		else
			print("none", x + 96, y + 8)
		end
	end

	if state == "found_weapon" then
		print_centered(
			"weapon found",
			"press ❎ to attack!"
		)
	end

	if state == "found_spell" then
		print_centered(
			"spell found",
			"press 🅾️ to cast!"
		)
	end

	if state == "gameover" then
		print_centered(
			"game over",
			"press ❎ to restart"
		)
	end

	if state == "win" then
		print_centered(
			"evil destroyed",
			"thanks for playing!"
		)
	end

	if debug_msg then
		print(debug_msg)
	end
end
-->8
-- lib

-- geometry

function ctr_tile(tx, ty, w, h)
	local x = tx * 8 + (8 - w) \ 2
	local y = ty * 8 + (8 - h) \ 2
	return x, y
end

function normal(v)
	if v.x == 0 and v.y == 0 then
		return v
	end

	local l = sqrt(v.x * v.x + v.y * v.y)
	if l < 1 then l = 1 end

	return { x = v.x / l, y = v.y / l }
end

function dist(v1, v2)
	local dx = v2.x - v1.x
	local dy = v2.y - v1.y
	return sqrt(dx * dx + dy * dy)
end

function dir_to(v1, v2)
	local dx = v2.x - v1.x
	local dy = v2.y - v1.y
	return normal({ x = dx, y = dy })
end

function overlaps(r1, r2)
	local disjoint = r1.x + r1.w < r2.x
			or r2.x + r2.w < r1.x
			or r1.y + r1.h < r2.y
			or r2.y + r2.h < r1.y
	return not disjoint
end

function overlaps_tile(r1, tx, ty)
	local r2 = { x = tx * 8, y = ty * 8, w = 8, h = 8 }
	return overlaps(r1, r2)
end

function lerp(a, b, t)
	return a + (b - a) * t
end

function in_room_bounds(r)
	return r.x >= room.tx * 8 + 8
			and r.y >= room.ty * 8 + 8
			and r.x + r.w <= room.tx * 8 + 120
			and r.y + r.h <= room.ty * 8 + 104
end

-- move

function try_move(e, dir, spd)
	if try_move_0(e, dir, spd) then
		return true
	end

	local xdir = normal({ x = dir.x, y = 0 })
	if try_move_0(e, xdir, spd) then
		return true
	end

	local ydir = normal({ x = 0, y = dir.y })
	if try_move_0(e, ydir, spd) then
		return true
	end

	return false
end

function try_move_0(e, dir, spd)
	local x = e.x + dir.x * spd
	local y = e.y + dir.y * spd
	local r = { x = x, y = y, w = e.w, h = e.h }

	if tile_collision(r) then
		return false
	end

	e.x, e.y = x, y
	return true
end

function tile_collision(r)
	local x1 = flr(r.x / 8)
	local y1 = flr(r.y / 8)
	local x2 = flr((r.x + r.w) / 8)
	local y2 = flr((r.y + r.h) / 8)

	for tx = x1, x2 do
		for ty = y1, y2 do
			local t = mget(tx, ty)
			if fget(t, 0) then
				return true
			end
		end
	end

	return false
end

-- attack

function mk_attack(e, dir, length, breadth, h_sprite, v_sprite, layer)
	local w, h, sprite, flip_x, flip_y
	if dir.y == 0 then
		w, h = length, breadth
		sprite = h_sprite
		flip_x = dir.x < 0
		flip_y = false
	else
		w, h = breadth, length
		sprite = v_sprite
		flip_x = false
		flip_y = dir.y < 0
	end

	local x = e.x + e.w / 2
			+ dir.x * e.w / 2
			+ dir.x * w / 2
			+ dir.x * 2
			- w / 2

	local y = e.y + e.h / 2
			+ dir.y * e.h / 2
			+ dir.y * h / 2
			+ dir.y * 2
			- h / 2

	return {
		x = x, y = y,
		w = w, h = h,
		sprite = sprite,
		flip_x = flip_x,
		flip_y = flip_y,
		layer = layer
	}
end

-- entity system

function entity_system()
	for _, e in pairs(room.entities) do
		e.update(e)
	end
end

-- hurtbox system

function hurtbox_system()
	for b in all(room.hurtboxes) do
		apply_hurtbox(b)
	end
end

function apply_hurtbox(b)
	for _, e in pairs(room.entities) do
		local hit = e.layer == b.layer
				and overlaps(e, b)

		if hit and not e.invincible then
			if e.kill then e.kill(e) end
			room.entities[e.id] = nil
		end
	end
end

-- exit system

function exit_system()
	local plyr = room.entities[0]
	if not plyr then return end

	for e in all(room.exits) do
		local on_exit = overlaps_tile(plyr, e.tx, e.ty)

		if on_exit then
			rooms[e.room]()
			spell_cnt = 1
			break
		end
	end
end

-- switch system

function switch_system()
	local plyr = room.entities[0]
	if not plyr then return end

	for s in all(room.switches) do
		local on_switch = overlaps_tile(plyr, s.tx, s.ty)

		if on_switch then
			local keep = s.exec()
			if not keep then
				del(room.switches, s)
			end
		end
	end
end

-- trigger system

function trigger_system()
	for t in all(room.triggers) do
		if t.check() then
			t.exec()
			del(room.triggers, t)
		end
	end
end

-- draw

function draw_body(body)
	local x1, y1 = body.x, body.y
	local x2 = body.x + body.w - 1
	local y2 = body.y + body.h - 1
	rectfill(x1, y1, x2, y2)
end

function draw_sprite(body)
	if body.big_sprite then
		draw_big_sprite(body)
	elseif body.tall_sprite then
		draw_tall_sprite(body)
	elseif body.long_sprite then
		draw_long_sprite(body)
	else
		draw_small_sprite(body)
	end
end

function draw_small_sprite(body)
	local x = body.x + (body.w - 8) / 2
	local y = body.y + (body.h - 8) / 2
	spr(
		body.sprite,
		x, y,
		1, 1,
		body.flip_x, body.flip_y
	)
end

function draw_big_sprite(body)
	if body.flashing then
		lighten_palette()
	end

	local x = body.x + (body.w - 16) / 2
	local y = body.y + (body.h - 16) / 2
	local s_0_0 = body.big_sprite
	local s_1_0 = body.big_sprite + 1
	local s_0_1 = body.big_sprite + 16
	local s_1_1 = body.big_sprite + 17

	if body.flip_x then
		s_0_0, s_1_0, s_0_1, s_1_1 = s_1_0, s_0_0, s_1_1, s_0_1
	end

	spr(
		s_0_0, x, y,
		1, 1,
		body.flip_x, body.flip_y
	)
	spr(
		s_1_0, x + 8, y,
		1, 1,
		body.flip_x, body.flip_y
	)
	spr(
		s_0_1, x, y + 8,
		1, 1,
		body.flip_x, body.flip_y
	)
	spr(
		s_1_1, x + 8, y + 8,
		1, 1,
		body.flip_x, body.flip_y
	)

	if body.flashing then
		pal()
	end
end

function draw_long_sprite(body)
	local x = body.x + (body.w - 16) / 2
	local y = body.y + (body.h - 8) / 2
	local s_0_0 = body.long_sprite
	local s_1_0 = body.long_sprite + 1

	spr(s_0_0, x, y)
	spr(s_1_0, x + 8, y)
end

function draw_tall_sprite(body)
	local x = body.x + (body.w - 8) / 2
	local y = body.y + (body.h - 16) / 2
	local s_0_0 = body.tall_sprite
	local s_0_1 = body.tall_sprite + 16

	spr(s_0_0, x, y)
	spr(s_0_1, x, y + 8)
end

function lighten_palette()
	for i = 0, 15 do
		local r, g, b = pal(i)
		pal(i, 7)
	end
end

function print_centered(msg, sub_msg)
	local x = 64 - #msg * 2 + room.tx * 8

	local y = 60 + room.ty * 8

	local sub_x = 64 - #sub_msg * 2 + room.tx * 8

	local sub_y = 68 + room.ty * 8
	print(msg, x, y, 7)
	print(sub_msg, sub_x, sub_y, 7)
end

-- input

function input_dir()
	local dx, dy = 0, 0
	if btn(0) then dx -= 1 end
	if btn(1) then dx += 1 end
	if btn(2) then dy -= 1 end
	if btn(3) then dy += 1 end

	if dx == 0 and dy == 0 then
		return { x = 0, y = 0 }
	end

	local l = sqrt(dx * dx + dy * dy)
	return { x = dx / l, y = dy / l }
end
-->8
-- entity

-- player

function mk_player(tx, ty)
	local body = mk_body(tx, ty, 4, 4)
	body.id = 0
	body.sprite = 39
	body.update = update_player
	body.layer = "player"
	body.state = "walk"
	body.dir = { x = 1, y = 0 }
	body.timer = 0
	return body
end

function update_player(me)
	local spd = 1.5
	local sprite = 39
	local step_sprite = 55
	local atk_length = 6
	local atk_breadth = 2
	local atk_h_sprite = 38
	local atk_v_sprite = 54
	local atk_duration = 0.25
	local atk_cooldown = 0.25

	if me.state == "walk" then
		-- decrement attack cooldown
		if me.timer > 0 then
			me.timer -= 1 / 30
		end

		-- attack
		local attacking = btn(5)
				and weapon
				and me.timer <= 0

		if attacking then
			me.attack = mk_attack(
				me,
				me.dir,
				weapon.length,
				weapon.breadth,
				weapon.h_sprite,
				weapon.v_sprite,
				"enemy"
			)
			add(
				room.hurtboxes,
				me.attack
			)
			me.state = "attack"
			me.timer = atk_duration
		end

		-- spell
		local casting = btn(4)
				and spell
				and spell_cnt > 0
				and me.timer <= 0

		if casting then
			local id = room.next_entity
			room.next_entity += 1
			room.entities[id] = mk_fireball(
				id,
				me,
				me.dir,
				"enemy"
			)
			me.state = "attack"
			me.timer = atk_duration
			spell_cnt -= 1
		end

		-- move
		local dir = input_dir()
		try_move(me, dir, spd)

		-- set dir
		local new_dir = dir.y == 0 and dir.x != 0
				or dir.x == 0 and dir.y != 0

		if new_dir then
			me.dir = dir
		end

		set_walk_frame(
			me,
			dir,
			sprite,
			step_sprite
		)

		return
	end

	if me.state == "attack" then
		me.timer -= 1 / 30
		if me.timer <= 0 then
			del(
				room.hurtboxes,
				me.attack
			)
			me.attack = nil
			me.state = "walk"
			me.timer = atk_cooldown
		end
		return
	end
end

-- shambler

function mk_shambler(id, tx, ty, sprite, wake_sprite, chase_sprite, step_sprite)
	local me = mk_body(tx, ty, 4, 4)
	me.id = id
	me.sprite = sprite
	me.layer = "enemy"
	me.update = update_shambler
	me.kill = kill_shambler
	me.state = "sleep"
	me.wake_sprite = wake_sprite
	me.chase_sprite = chase_sprite
	me.step_sprite = step_sprite
	return me
end

function mk_mossman(id, tx, ty)
	return mk_shambler(
		id, tx, ty,
		17, 8, 8, 24
	)
end

function mk_zombie(id, tx, ty)
	return mk_shambler(
		id, tx, ty,
		18, 15, 30, 14
	)
end

function update_shambler(me)
	local wake_dist = 24
	local wake_duration = 0.5
	local wake_sprite = 8
	local spd = 0.75

	local plyr = room.entities[0]
	if not plyr then return end

	if me.state == "sleep" then
		if dist(me, plyr) < wake_dist then
			me.state = "wake"
			me.timer = wake_duration
			me.sprite = me.wake_sprite
			me.hurtbox = {
				x = me.x,
				y = me.y,
				w = me.w,
				h = me.h,
				layer = "player"
			}
			add(
				room.hurtboxes,
				me.hurtbox
			)
		end
	end

	if me.state == "wake" then
		me.timer -= 1 / 30
		if me.timer <= 0 then
			me.state = "chase"
		end
	end

	if me.state == "chase" then
		local dir = dir_to(me, plyr)
		try_move(me, dir, spd)
		me.hurtbox.x = me.x
		me.hurtbox.y = me.y

		set_walk_frame(
			me,
			dir,
			me.chase_sprite,
			me.step_sprite
		)
	end
end

function kill_shambler(me)
	if me.hurtbox then
		del(
			room.hurtboxes,
			me.hurtbox
		)
	end
end

-- imp

function mk_imp(id, tx, ty)
	local me = mk_body(tx, ty, 4, 4)
	me.id = id
	me.sprite = 40
	me.layer = "enemy"
	me.update = update_imp
	me.kill = kill_imp
	me.state = "roost"
	me.timer = 0
	me.hurtbox = {
		x = me.x,
		y = me.y,
		w = 4,
		h = 4,
		layer = "player"
	}
	add(room.hurtboxes, me.hurtbox)
	return me
end

function update_imp(me)
	local spd = 45
	local roost_dur = 1
	local sprite = 40
	local flap_sprite = 56

	if me.state == "roost" then
		me.timer += 1 / 30
		if me.timer >= roost_dur then
			local bx = flr(rnd(112)) + 9
			local by = flr(rnd(96)) + 9
			bx += room.tx * 8
			by += room.ty * 8
			me.pt_a = { x = me.x, y = me.y }
			me.pt_b = { x = bx, y = by }
			me.dur = dist(me, me.pt_b) / spd
			me.timer = 0
			me.state = "fly"
		end
	else
		me.timer += 1 / 30
		local t = me.timer / me.dur

		local x = lerp(
			me.pt_a.x,
			me.pt_b.x,
			t
		)

		local y = lerp(
			me.pt_a.y,
			me.pt_b.y,
			t
		)

		me.x, me.y = x, y
		me.hurtbox.x = x
		me.hurtbox.y = y

		local f = flr(time() * 12) % 2
		if f == 0 then
			me.sprite = sprite
		else
			me.sprite = flap_sprite
		end

		if me.timer >= me.dur then
			me.state = "roost"
			me.timer = 0
		end
	end
end

function kill_imp(me)
	del(
		room.hurtboxes,
		me.hurtbox
	)
end

-- fireball

function mk_fireball(id, parent, dir, layer)
	local x = parent.x + parent.w / 2 - 2
	local y = parent.y + parent.h / 2 - 2
	local me = { x = x, y = y, w = 4, h = 4 }
	me.id = id
	me.sprite = 16
	me.layer = "projectile"
	me.update = update_fireball
	me.sprite = 53
	me.state = "fly"
	me.dir = dir
	me.timer = 0
	me.hurtbox = {
		x = me.x,
		y = me.y,
		w = me.w,
		h = me.h,
		layer = layer
	}
	add(room.hurtboxes, me.hurtbox)
	return me
end

function update_fireball(me)
	local spd = 2.5
	local max_dur = 1.5

	if me.state == "fly" then
		if me.timer >= max_dur then
			del(room.hurtboxes, me.hurtbox)
			room.entities[me.id] = nil
			return
		end

		local col = try_move_0(me, me.dir, spd)
		if not col then
			del(room.hurtboxes, me.hurtbox)
			room.entities[me.id] = nil
		end

		me.hurtbox.x = me.x
		me.hurtbox.y = me.y
		me.timer += 1 / 30
		return
	end
end

-- knight

function mk_knight(id, tx, ty)
	local me = mk_body(tx, ty, 12, 12)
	me.id = id
	me.big_sprite = 9
	me.layer = "enemy"
	me.update = update_knight
	me.kill = kill_knight
	me.dir = { x = -1, y = 0 }
	me.hurtbox = {
		x = me.x,
		y = me.y,
		w = 12,
		h = 12,
		layer = "player"
	}
	me.swrd_box = {
		x = me.x - 16,
		y = me.y + me.h / 2 - 2,
		w = 12,
		h = 6,
		layer = "player",
		long_sprite = 41
	}
	add(room.hurtboxes, me.hurtbox)
	add(room.hurtboxes, me.swrd_box)
	return me
end

function update_knight(me)
	local spd = 1.25

	local plyr = room.entities[0]
	if not plyr then return end

	local ctr_y = me.y + me.h / 2
	local plyr_y = plyr.y + plyr.h / 2
	local dy
	if plyr_y < ctr_y then dy = -1 else dy = 1 end
	if abs(plyr_y - ctr_y) <= 1 then dy = 0 end
	local dir = { x = 0, y = dy }

	try_move(me, dir, spd)
	me.hurtbox.x, me.hurtbox.y = me.x, me.y
	me.swrd_box.y = me.y + me.h / 2 - 2
	me.flip_x = flr(time() * 2) % 2 == 1
end

function kill_knight(me)
	del(room.hurtboxes, me.hurtbox)
	del(room.hurtboxes, me.swrd_box)
end

-- tree

function mk_tree(id, tx, ty)
	local me = mk_body(tx, ty, 12, 12)
	me.x += 4
	me.y += 4
	me.id = id
	me.big_sprite = 12
	me.layer = "enemy"
	me.update = update_tree
	me.timer = 5
	return me
end

function update_tree(me)
	local dur = 2
	local flash_dur = 0.2

	local plyr = room.entities[0]
	if not plyr then return end

	me.timer -= 1 / 30
	if me.timer <= 0 then
		local x = plyr.x + plyr.w / 2 - 2
		local y = plyr.y + 8
		local id = room.next_entity
		room.entities[id] = mk_root(id, x, y, me.id)

		room.next_entity += 1
		me.timer = dur
	end

	if me.flashing then
		me.flash_timer += 1 / 30
		if me.flash_timer >= flash_dur then
			me.flashing = false
		end
	end

	me.flip_x = flr(time() * 2) % 2 == 1
end

-- root

function mk_root(id, x, y, tree_id)
	local me = { x = x, y = y, w = 4, h = 8 }
	me.id = id
	me.sprite = 11
	me.layer = "enemy"
	me.update = update_root
	me.kill = kill_root
	me.timer = 0
	me.state = "grow"
	me.hurtbox = {
		x = me.x,
		y = me.y,
		w = me.w,
		h = me.h,
		layer = "player"
	}
	me.tree_id = tree_id
	add(room.hurtboxes, me.hurtbox)
	return me
end

function update_root(me)
	local dur = 0.5

	if me.state == "grow" then
		me.timer += 1 / 30
		if me.timer >= dur then
			me.state = "grown"
			me.tall_sprite = 11
			me.height = 12
			me.y -= 4
			me.timer = 0
			del(room.hurtboxes, me.hurtbox)
			me.hurtbox = {
				x = me.x,
				y = me.y,
				w = 4,
				h = 12,
				layer = "player"
			}
			add(room.hurtboxes, me.hurtbox)
		end
	elseif me.state == "grown" then
		me.timer += 1 / 30
		if me.timer >= dur then
			del(room.hurtboxes, me.hurtbox)
			room.entities[me.id] = nil
		end
	end
end

function kill_root(me)
	del(room.hurtboxes, me.hurtbox)
	room.roots_killed += 1

	if me.tree_id then
		local tree = room.entities[me.tree_id]
		if tree then
			tree.flashing = true
			tree.flash_timer = 0
		end
	end
end

-- orb

function mk_orb(id, tx, ty)
	local me = mk_body(tx, ty, 4, 4)
	me.id = id
	me.sprite = 59
	me.layer = "enemy"
	me.update = update_orb
	me.kill = kill_orb
	me.timer = 0
	return me
end

function update_orb(me)
	me.flip_x = flr(time() * 2) % 2 == 1
end

function kill_orb(me)
	room.orbs_killed += 1
end

-- ghost

function mk_ghost(id, tx, ty)
	local me = mk_body(tx, ty, 4, 4)
	me.id = id
	me.sprite = 46
	me.update = update_ghost
	me.kill = kill_ghost
	me.hurtbox = {
		x = me.x,
		y = me.y,
		w = me.w,
		h = me.h,
		layer = "player"
	}
	me.state = "wait"
	me.timer = 0
	add(room.hurtboxes, me.hurtbox)
	return me
end

function update_ghost(me)
	local wait_dur = 1.5
	local spd = 2.5

	local plyr = room.entities[0]
	if not plyr then return end

	me.flip_x = flr(time() * 2) % 2 == 1

	if me.state == "wait" then
		me.timer += 1 / 30
		if me.timer >= wait_dur then
			local dx = plyr.x - me.x
			local dy = plyr.y - me.y
			local dist = sqrt(dx * dx + dy * dy)
			local dir = { x = dx / dist, y = dy / dist }

			me.state = "fly"
			me.dir = dir
			me.timer = dist * 1.5 / 30 / spd
		end
	elseif me.state == "fly" then
		me.timer -= 1 / 30
		if me.timer <= 0 then
			me.state = "wait"
			me.timer = 0
		else
			local new_x = me.x + me.dir.x * spd
			local new_y = me.y + me.dir.y * spd
			local r = { x = new_x, y = new_y, w = me.w, h = me.h }
			if in_room_bounds(r) then
				me.x = new_x
				me.y = new_y
				me.hurtbox.x = new_x
				me.hurtbox.y = new_y
			else
				me.timer = 0
				me.state = "wait"
			end
		end
	end
end

function kill_ghost(me)
	del(room.hurtboxes, me.hurtbox)
end

-- phantom

function mk_phantom(id, x, y)
	local me = { x = x, y = y, w = 12, h = 12 }
	me.id = id
	me.big_sprite = 44
	me.layer = "enemy"
	me.update = update_phantom
	me.kill = kill_phantom
	me.hurtbox = {
		x = me.x,
		y = me.y,
		w = 12,
		h = 12,
		layer = "player"
	}
	me.timer = 10
	me.state = "wait"
	add(room.hurtboxes, me.hurtbox)
	return me
end

function update_phantom(me)
	local wait_dur = 1.5
	local spd = 2.5

	local plyr = room.entities[0]
	if not plyr then return end

	me.flip_x = flr(time() * 2) % 2 == 1

	if me.state == "wait" then
		me.timer += 1 / 30
		if me.timer >= wait_dur then
			local dx = plyr.x - me.x
			local dy = plyr.y - me.y
			local dist = sqrt(dx * dx + dy * dy)
			local dir = { x = dx / dist, y = dy / dist }

			me.state = "fly"
			me.dir = dir
			me.timer = dist / 30 / spd
		end
	elseif me.state == "fly" then
		me.timer -= 1 / 30
		if me.timer <= 0 then
			me.state = "wait"
			me.timer = 0
		else
			local new_x = me.x + me.dir.x * spd
			local new_y = me.y + me.dir.y * spd
			local r = { x = new_x, y = new_y, w = me.w, h = me.h }
			me.x = new_x
			me.y = new_y
			me.hurtbox.x = new_x
			me.hurtbox.y = new_y
		end
	end
end

function kill_phantom(me)
	del(room.hurtboxes, me.hurtbox)
	room.phantom_killed = true
end

-- king

function mk_king(id, tx, ty)
	local me = mk_body(tx, ty, 12, 12)
	me.id = id
	me.big_sprite = 66
	me.layer = "enemy"
	me.update = update_king
	me.kill = kill_king
	me.hurtbox = {
		x = me.x,
		y = me.y,
		w = me.w,
		h = me.h,
		layer = "player"
	}
	me.state = "idle"
	me.timer = 0

	if room.king_hits == 1 then
		me.dirx = 1
	else
		me.dirx = -1
	end

	me.flip_x = me.dirx > 0
	add(room.hurtboxes, me.hurtbox)

	if room.king_hits >= 1 then
		local shield_x
		if me.dirx > 0 then
			shield_x = me.x + 8
		else
			shield_x = me.x - 2
		end
		me.shield_box = {
			x = shield_x,
			y = me.y + me.h / 2 - 6,
			w = 6,
			h = 8,
			layer = "player",
			big_sprite = 72,
			flip_x = me.flip_x
		}
		add(room.hurtboxes, me.shield_box)
	end

	return me
end

function update_king(me)
	local align_spd = 1.0
	local idle_dur = 1.0
	local charg_dur = 1.0

	local plyr = room.entities[0]
	if not plyr then return end

	if me.state == "idle" then
		me.timer += 1 / 30

		if me.shield_box then
			me.invincible = true
		end

		-- align with player
		local dy = plyr.y + plyr.h / 2 - me.y - me.h / 2
		if abs(dy) >= align_spd then
			me.y += dy / abs(dy) * align_spd
			me.hurtbox.y = me.y
			if me.shield_box then
				me.shield_box.y = me.y + me.h / 2 - 4
			end
		end

		if me.timer >= idle_dur then
			me.state = "charge"
			me.timer = 0
			me.big_sprite = 70
			me.swrd_box = {
				x = me.x - 12 * -me.dirx,
				y = me.y + me.h / 2 - 2,
				w = 12,
				h = 6,
				layer = "player",
				big_sprite = 68,
				flip_x = me.flip_x
			}
			del(room.hurtboxes, me.shield_box)
			add(room.hurtboxes, me.swrd_box)
			me.invincible = false
		end
	elseif me.state == "charge" then
		me.timer += 1 / 30
		if me.timer >= charg_dur then
			me.state = "idle"
			me.timer = 0
			me.big_sprite = 66
			del(room.hurtboxes, me.swrd_box)
			me.swrd_box = nil
			add(room.hurtboxes, me.shield_box)
		end
	end
end

function kill_king(me)
	if me.swrd_box then
		del(room.hurtboxes, me.swrd_box)
	end

	del(room.hurtboxes, me.hurtbox)

	room.king_hits += 1
end

-- util

function mk_body(tx, ty, w, h)
	local x, y = ctr_tile(tx, ty, w, h)
	return { x = x, y = y, w = w, h = h }
end

function set_walk_frame(me, dir, sprite, step_sprite)
	if dir.x == 0 and dir.y == 0 then
		me.sprite = sprite
	else
		local f = flr(time() * 12) % 4
		if f == 0 or f == 2 then
			me.sprite = sprite
			me.flip_x = false
		else
			me.sprite = step_sprite
			me.flip_x = f == 3
		end
	end
end
-->8
-- room

rooms = {}

-- room 1: entrance

function room_1(id, x, y)
	return function()
		room_id = id
		room = mk_room("entrance", 0, 0)

		add_exit(3, 13, 201)
		add_exit(4, 13, 201)
		add_exit(15, 4, 401)
		add_exit(15, 5, 401)

		add_switch(
			10, 3,
			function()
				-- destroy switch
				set_tile(10, 3, 0)
				-- drain fountain
				set_tile(10, 10, 0)
				set_tile(11, 10, 0)
				set_tile(10, 9, 0)
				set_tile(10, 11, 0)
				set_tile(9, 10, 0)
				set_tile(8, 10, 0)
				-- spawn knife
				set_tile(10, 10, 32)
			end
		)

		add_switch(
			10, 10,
			function()
				-- despawn knife
				set_tile(10, 10, 0)
				-- set player weapon
				if not weapon then
					weapon = player_knife
					state = "found_weapon"
				end
			end
		)

		add_player(x, y)
		add_enemy(10, 3, mk_mossman)

		add_trigger(
			function()
				-- when mossman dies
				return not room.entities[1]
			end,
			function()
				-- open doors
				set_tile(15, 4, 0)
				set_tile(15, 5, 0)
			end
		)
	end
end

rooms[101] = room_1(101, 5, 3)
rooms[102] = room_1(102, 3, 12)
rooms[103] = room_1(103, 14, 4)

-- room 2

function room_2(id, x, y)
	return function()
		room_id = id
		room = mk_room("cemetery", 0, 1)

		add_exit(3, 0, 102)
		add_exit(4, 0, 102)
		add_exit(12, 5, 301)

		add_player(x, y)
		add_enemy(7, 4, mk_zombie)

		-- don't add enemy right next to spawn point
		if id ~= 202 then
			add_enemy(11, 5, mk_zombie)
		end

		add_enemy(2, 8, mk_zombie)
		add_enemy(5, 9, mk_zombie)
	end
end

rooms[201] = room_2(201, 3, 1)
rooms[202] = room_2(202, 12, 6)

-- room 3

function room_3()
	room_id = 301
	room = mk_room("crypt", 1, 1)

	add_exit(2, 6, 202)

	add_player(3, 6)
	add_enemy(9, 6, mk_knight)

	add_switch(
		13, 2, function()
			set_tile(13, 2, 0)
			blue_key = true
		end
	)

	add_switch(
		13, 11, function()
			weapon = player_sword
			set_tile(13, 11, 0)
		end
	)

	add_trigger(
		function()
			-- when knight dies
			return not room.entities[1]
		end,
		function()
			-- open door
			set_tile(11, 6, 0)
			set_tile(11, 7, 0)
		end
	)
end

rooms[301] = room_3

-- room 4

function room_4(id, x, y)
	return function()
		room_id = id
		room = mk_room("foyer", 1, 0)

		add_exit(0, 4, 103)
		add_exit(0, 5, 103)
		add_exit(15, 6, 501)
		add_exit(15, 7, 501)
		add_exit(8, 2, 701)

		add_player(x, y)

		add_enemy(5, 5, mk_imp)
		add_enemy(12, 5, mk_imp)
		add_enemy(7, 11, mk_imp)

		add_trigger(
			function()
				return all_enemies_dead()
			end,
			function()
				set_tile(8, 4, 0)
				set_tile(15, 6, 0)
				set_tile(15, 7, 0)
			end
		)
	end
end

rooms[401] = room_4(401, 1, 5)
rooms[402] = room_4(402, 14, 7)
rooms[403] = room_4(403, 8, 3)

-- room 5: library

function room_5(id, x, y)
	return function()
		room = mk_room("library", 2, 0)

		add_exit(0, 6, 402)
		add_exit(0, 7, 402)
		add_exit(7, 13, 601)
		add_exit(8, 13, 601)

		-- rest book tiles
		set_tile(3, 3, 51)
		set_tile(5, 3, 4)
		set_tile(7, 3, 35)
		set_tile(3, 10, 4)
		set_tile(5, 10, 35)
		set_tile(7, 10, 19)

		add_player(x, y)

		function book_switch(x, y, id)
			return function()
				room.book = id
				set_tile(x, y, 0)
			end
		end

		add_switch(
			3, 3,
			book_switch(3, 3, 51)
		)

		add_switch(
			5, 3,
			book_switch(5, 3, 4)
		)

		add_switch(
			7, 3,
			book_switch(7, 3, 35)
		)

		add_switch(
			3, 10,
			book_switch(3, 10, 4)
		)

		add_switch(
			5, 10,
			book_switch(5, 10, 35)
		)

		add_switch(
			7, 10,
			book_switch(7, 10, 19)
		)

		add_switch(
			10, 6,
			function()
				if room.book == 35 then
					set_tile(11, 6, 0)
				else
					return true
				end
			end
		)

		add_switch(
			13, 6,
			function()
				set_tile(13, 6, 0)
				spell = true
				state = "found_spell"
			end
		)
	end
end

rooms[501] = room_5(501, 1, 6)
rooms[502] = room_5(502, 7, 12)

-- room 6: garden

function room_6(id, x, y)
	return function()
		room_id = id
		room = mk_room("garden", 2, 1)
		room.roots_killed = 0

		add_exit(7, 0, 502)
		add_exit(8, 0, 502)

		add_player(x, y)

		add_enemy(7, 11, mk_tree)

		add_switch(
			5, 12, function()
				set_tile(5, 12, 0)
				green_key = true
			end
		)

		add_trigger(
			function()
				return room.roots_killed >= 2
			end,
			function()
				set_tile(7, 9, 0)
				set_tile(8, 9, 0)
			end
		)

		add_trigger(
			function()
				return not room.entities[1]
			end,
			function()
				set_tile(6, 12, 0)
			end
		)
	end
end

rooms[601] = room_6(601, 7, 1)

-- room 7: hall

function room_7(id, x, y)
	return function()
		room_id = id
		room = mk_room("hall", 3, 0)

		add_exit(8, 2, 403)
		add_exit(8, 13, 801)
		add_exit(15, 5, 901)

		add_player(x, y)

		add_enemy(4, 5, mk_imp)

		if id ~= 702 then
			add_enemy(8, 11, mk_imp)
		end

		add_enemy(12, 5, mk_imp)

		add_trigger(
			function()
				return blue_key
			end,
			function()
				set_tile(13, 5, 0)
			end
		)

		add_trigger(
			function()
				return green_key
			end,
			function()
				set_tile(14, 5, 0)
			end
		)

		add_trigger(
			function()
				return red_key
			end,
			function()
				set_tile(15, 5, 0)
			end
		)

		add_trigger(
			function()
				return all_enemies_dead()
			end,
			function()
				set_tile(8, 13, 0)
			end
		)
	end
end

rooms[701] = room_7(701, 8, 3)
rooms[702] = room_7(702, 8, 12)
rooms[703] = room_7(703, 14, 5)

-- room 8: observatory

function room_8(id, x, y)
	return function()
		room_id = id
		room = mk_room("observatory", 3, 1)
		room.orbs_killed = 0

		add_exit(8, 0, 702)

		add_player(x, y)

		add_enemy(4, 7, mk_orb)
		add_enemy(12, 7, mk_orb)
		add_enemy(8, 10, mk_orb)
		add_enemy(8, 9, mk_ghost)

		add_switch(
			8, 12, function()
				set_tile(8, 12, 0)
				red_key = true
			end
		)

		add_trigger(
			function()
				return room.orbs_killed >= 3
			end,
			function()
				local x = room.entities[4].x
						+ room.entities[4].w / 2
						- 6
				local y = room.entities[4].y
						+ room.entities[4].h / 2
						- 6
				room.entities[4].kill(room.entities[4])
				room.entities[4] = nil
				room.entities[5] = mk_phantom(5, x, y)
				room.next_entity = 6
				room.phantom = true
			end
		)

		add_trigger(
			function()
				return room.phantom_killed
			end,
			function()
				set_tile(8, 11, 0)
			end
		)
	end
end

rooms[801] = room_8(801, 8, 1)

-- room 9: throne room

function room_9(id, x, y)
	return function()
		room_id = id
		room = mk_room("throne room", 4, 0)
		room.king_hits = 0

		add_exit(0, 5, 703)

		add_enemy(10, 6, mk_king)

		add_player(x, y)

		add_trigger(
			function()
				return room.entities[1] == nil
						and room.king_hits == 1
			end,
			function()
				add_enemy(5, 6, mk_king)
			end
		)

		add_trigger(
			function()
				return room.entities[1] == nil
						and room.king_hits == 2
			end,
			function()
				add_enemy(10, 6, mk_king)
			end
		)

		add_trigger(
			function()
				return room.entities[1] == nil
						and room.king_hits >= 3
			end,
			function()
				state = "win"
			end
		)
	end
end

rooms[901] = room_9(901, 1, 5)

-- util

function mk_room(name, x, y)
	camera(x * 16 * 8, y * 16 * 8)
	return {
		name = name,
		entities = {},
		hurtboxes = {},
		next_hurtbox_id = 1,
		tx = x * 16,
		ty = y * 16 + 2,
		exits = {},
		switches = {},
		triggers = {},
		next_entity = 1
	}
end

function add_exit(x, y, id)
	add(
		room.exits, {
			tx = room.tx + x,
			ty = room.ty + y,
			room = id
		}
	)
end

function add_player(x, y)
	room.entities[0] = mk_player(room.tx + x, room.ty + y)
end

function add_enemy(x, y, f)
	local id = room.next_entity
	room.next_entity += 1
	room.entities[id] = f(
		id,
		x + room.tx,
		y + room.ty
	)
end

function add_switch(x, y, exec)
	add(
		room.switches, {
			tx = room.tx + x,
			ty = room.ty + y,
			exec = exec
		}
	)
end

function add_trigger(check, exec)
	add(
		room.triggers, {
			check = check,
			exec = exec
		}
	)
end

function set_tile(x, y, id)
	mset(
		room.tx + x,
		room.ty + y,
		id
	)
end

function all_enemies_dead()
	for id, _ in pairs(room.entities) do
		if id > 0 then
			return false
		end
	end
	return true
end

__gfx__
00000000066666600006600000000000000000000000000000000000000000000033330000000ccaacc00000000000000000000000000040000cc00000044000
0000000066666666006666000444444000ccccc0000000000a0aa0a000000000033333300000aacaacaa000000040000000003333330040000c4c40000444400
000000006655565606666660044444400c7777000bbb000000a88a000a0000003353353300acccaaaaccca000004003004403343333444000c1c41c004144140
000000006666666606655660046516400cccccc00b0bbbb00a8778a00acccccc333333330ccacccccccca000000443004004443333443000cc7117cc44711744
000000006565556606666660047517400cccccc00bbb0bb00a8778a00accccc033355333cccac55cc55cacc0000440000033344334443300c411114c44111144
000000006666666606555560044444400cccccc00000000000a88a000a00000030355303ccccc555555ccccc003344000333455445543334c0c11c0c40411404
0000000066555656066666600486d74000ccccc0000000000a0aa0a00000000000333300ccccccc55ccccccc00304400033455544555433004ccc40000444400
000000000666666006555560004444000000000000000000000000000000000003300330aaa11cc55cc11aaa00004400444454444445444000000c4004400440
000000000033330004444440000000000000000000000000000000000000000000333300aaa1ccc55ccc1aaa000440000344444444444430000cc00006666660
0000000003333330444444440088888000000000000000000a0000a000aaaa0003333330aaa0ccccccc10aaa03344000033444455444433000c4c40066555566
77700777335333334444004408777700000000000ccc000000000000000cc00033533533a000aaaccaaa0aaa0344000000333455554333000c1c41c066555566
75577557333355334444444408888880006666000c0cccc000080000000cc00033333333000cccaaaaccc00a004400000000045555400000cc7117cc06666660
77757777333333334004444408888880056666500ccc0cc000008000000cc0003335533300accccccccccc00004400000000045445400000c411114c05655650
75577557333333334444444408888880065555600000000000000000000cc0003035530300aaaaa00cccca00004433000044444444400000c0c11c0c65655656
8887588833553333444400440088888006666660000000000a0000a0000cc000033333000aaaaaa00aaaaa0000044000044444444444000000ccc40065655656
000880000333333004444440000000000000000000000000000000000000c00000000330000000000aaaaaa000044000000044444444440004c00c4006666660
00000000000440005555555500000000000660000000000000000000000cc00000000000000000000000000008888880000000a00a000000000550009aa9aa9a
00000000000440006666666600aaaaa006611660000000000000000000cccc00800880080000000000000aa08880088800000aa88aa000000055550022222222
00a0000000044000666666660a777700615115160888000000a000000cccccc08888888800000000000000aa880000880000088aa88000000555555022222222
0aa77700000a4000055555500aaaaaa0615115160808888000a77700cc5555cc08855880000cccccccccccaa8800008800008855558800005575575522882222
0aa77000000a4000066666600aaaaaa0615115160888088000a77000ccc55ccc0088880000000cccccccccaa8880088800088875578880000555555022222222
00a0000000044000066666600aaaaaa0666666660000000000a00000c0cccc0c0080080000000000000000aa8800008800882855558288000055500022222222
00000000000440000055550000aaaaa066556566000000000000000000cccc00087007800000000000000aa08800008808802885558208800005550022228882
000000000004400000666600000000000666666000000000000000000cc00cc00000000000000000000000000888888008000285582000800000050022222222
000000000cccccc00000000000000000006666600000000000000000000cc000000000000cccccc00bbbbbb000cccc0008000085580000800666666022222222
00000000cccccccc0000000000bbbbb006111666000000000000000000cccc0000088000ccc00cccbbb00bbb0ccc77c008000885280000806558865622228822
00a00000cccc77cc000000000b77770006555656000aa00000aaaa000cccccc088888888cc0000ccbb0000bbcc8ccc7c000088528800000066c88c6622222222
aaaccccccccccccc444444440bbbbbb06111166600a88a0000077000cc5555cc88855888cc0000ccbb0000bbccc88ccc00008852800000006b8cbcb622282222
aaacccc0c7cccccc444aa4440bbbbbb06111165600a88a0000077000ccc55ccc00888800ccc00cccbbb00bbbccc88ccc00008882800000006cbcbb8622222222
00a00000ccc77ccc000000000bbbbbb006555656000aa00000007000c0cccc0c00800800cc0000ccbb0000bbc7ccc8cc00000888880000006ccbcbc628222222
00000000cccccccc0000000000bbbbb00611166600000000000000000ccccc0087000078cc0000ccbb0000bb0c77ccc000000088888000006bbbccb622222222
000000000cccccc0000000000000000000666660000000000000000000000cc0000000000cccccc00bbbbbb000cccc00000000000080000006666660a99aa9aa
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000c000a0a0a0000000000000000000000a0a0a00000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000ccc00a8a8a0343000000000000000000a8a8a00000000000000000000000000000000000000000000000000000000000000000000000000
00099999999900090cdc008aaa800343000000000000000008aaa8000003000000000ccccc000000000000000000000000000000000000000000000000000000
00044444444409990cdc008575800040000000000000000008575800003400000000ccccccc00000000000000000000000000000000000000000000000000000
00002288224094490cdc008757880040000000000000000008757880004030000000ccdddcc00000000000000000000000000000000000000000000000000000
00022888822944490cdc008822883440000000000099000008822883440000800000ccdddcc00000000000000000000000000000000000000000000000000000
00028882882444490cdc002888283300000cccccccc9000002828283300008800000cdddddc00000000000000000000000000000000000000000000000000000
00028828882444499ccc92202228880000ccddddddc9000022082288000088000000cdddddc00000000000000000000000000000000000000000000000000000
00022888822944499999920008228800000cccccccc9000020008228800080000000cdddddc00000000000000000000000000000000000000000000000000000
00002288224094490222200008228800000000000099000000008222882880000000ccdddcc00000000000000000000000000000000000000000000000000000
00044444444409990040000082288000000000000000000000008822228800000000ccdddcc00000000000000000000000000000000000000000000000000000
00099999999900090040000822880000000000000000000000000088888000000000ccccccc00000000000000000000000000000000000000000000000000000
000000000000000000000008888000000000000000000000000000000000000000000ccccc000000000000000000000000000000000000000000000000000000
00000000000000000000008800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000088000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0001010100000000000000000000000000010000000000000000000000000001000100000100000000000001000000000001010000000000000101000000010001010000000000000000000000000000010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111111111111111111111111111111101012424240101010101010124240101010101010101010101010101010101010101012424240101010124242401010101013e3e3e24242424243e3e3e240101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11000000000000000000000000000001010000000000010101010100000000010100000000000000000000000000000101000000000000000100000000000001010000000000001f0000000000000034000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
110000000000000000000000000000343400001f0000010022000100001f0001010003030303030303030303030300013400000000000000220000000000000101000000001f1f1f1f1f000000000034000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
110000000000000011001400110001010100001f0000010000000100000000010100033303040323030000000000000134000000000000000000000000000001010000001f00001f00001f0000000034000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000002100000000000001013201010000000001010000000000000000000303000000013400001f00001f0000001f00000101010100001f0000001f0000001f0000003e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11000000000000000000000000000021000000000000000000000000000001010100000000000000000013030303030101000000000000000000000000393a2b0000000000000000000000000000003e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000110011001100010101000000000000000000000000000021000000000000000000000003001000013400001f00001f0000001f00000101010100000000000000000000000040413e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
110000000000000000000000000000343400000000000000000000000000002100000000000000000000330300000001340000000000000000000000000000010100000000000000000000000050513e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
110000000000000000000100000000010100001f1f00001f00001f1f0000010101000000000000000000040303030301010000000000000000000000000000010100000000000000000000000000003e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000131010000001101000000000000000000000000000001010000000000000000000303000000013400000000001f0000001f00000000010100001f0000001f0000001f0000003e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11000000000000000131313101000011010000000000000000000000000000010100030403230313030000000000000134000000000000000000000000000001010000001f00001f00001f0000000034000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
110000000000000000013101000000110100001f1f00001f00001f1f00000001010003030303030303030303030300013400000000001f0000001f000000000101000000001f1f1f1f1f000000000034000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11000100000100000000010000000011010000000000000000000000000000010100000000000000000000000000000101000000000000000000000000000001010000000000001f0000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1101010000010111111111111111111101012424240101242401012424240101010101010101010000010101010101010124242424010101320101012424240101013e3e3e24242424243e3e3e240101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1101010000010111111111111111110101010101010101010101010101010101111111111111110000111111111111110124242424010101000101012424240100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000000101010101010101010101010100000001110000000000000000000000000000113400000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000000101010101010101010101010100150001110000000000110000110000000000113400000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
110000000000000200000000000000010101010100000000000000010000000111000000000000000000000000000011340000001f1f00000000001f1f00003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000020200000101010101000000000000000100000001110000000000110000110000000000113400000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000200000000000002001200000101000000000000000000000100000001110000000000000000000000000000113400000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
110000000000020000000000000000010100120000000000000000210000000111001101110000000000001101110011340000001f1f00000000001f1f00003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11000200000000000002000002000001010012000000000000000021000000011100013101000000000000013101001134000000001f00000000001f0000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000020000000000000000000101000000000000000000000100000001110011011100000000000011011100113400000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000200000101010101000000000000000100000001110000000011111111111100000000113400000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
110000000002000000020000000000010101010100000000000000010000000111000000111100000000111100000011340000001f1f00000000001f1f00003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100020000000000000000000000000101010101010101010101010100300001110000001101000000000111000000113400000000000024242400000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000000101010101010101010101010100000001110000110105010000013101110000113400000000000024252400000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111111111111111111111111111111101010101010101010101010101010101111111111111111111111111111111110124242424242424242424242424240100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
