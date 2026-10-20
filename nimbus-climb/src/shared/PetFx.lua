--[[
	PetFx (Phase 6): the effects of evolved pets - auras, particles, lights and glow pulses.
	Effects are not models (no Parts, no meshes of their own): they live on invisible Attachments of the pet's Body root,
	so they work for both the Part-built pets and the Blender mesh pets. Contract: ARCHITECTURE_V3.md "## Phase 6" 6.4.

	PetFx.Apply(model, look, stage, opts) -> nothing   (stage 1 / 2 = first / second evolution; 0 does nothing)
	PetFx.Clear(model)
]]

local PetFx = {}

function PetFx.Apply(model, look, stage, opts)
	-- filled in by the Phase 6 evofx engineer
end

function PetFx.Clear(model)
	local root = model and model:FindFirstChild("Body")
	local fx = root and root:FindFirstChild("PetFx")
	if fx then
		fx:Destroy()
	end
end

return PetFx
