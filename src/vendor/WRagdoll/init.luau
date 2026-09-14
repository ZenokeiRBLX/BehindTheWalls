--[[

	Wo's Ragdoll (WRagdoll), vendored from the Studio copy.
	Joint limits live in the 'Joints' ModuleScript next to this one.

]]

local module = {}

local Limits = require(script.Joints)

function module:TurnRagdoll(Humanoid)
	assert(Humanoid and Humanoid:IsA("Humanoid"), "'Humanoid' parameter is not a humanoid!")
	local Character = Humanoid.Parent
	local isragdoll = not module:IsRagdoll(Humanoid)
	Humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, not isragdoll)
	task.defer(Humanoid.ChangeState, Humanoid, isragdoll and Enum.HumanoidStateType.Ragdoll or Enum.HumanoidStateType.GettingUp)
	local Attachments = {}
	
	for _, obj in ipairs(Character:GetDescendants()) do
		if string.find(obj.Name, "RigA") and obj.Parent ~= Character.PrimaryPart then
			if not Attachments[obj.Name] then
				Attachments[obj.Name] = obj
			elseif isragdoll then
				local Attach0 = Attachments[obj.Name]
				local Attach1 = obj

				local BallSocket = Instance.new("BallSocketConstraint")
				BallSocket.Attachment0 = Attach1
				BallSocket.Attachment1 = Attach0

				local register = Limits[obj.Name]

				BallSocket.MaxFrictionTorque = register and register.MaxFrictionTorque or 2
				BallSocket.LimitsEnabled = true
				BallSocket.UpperAngle = register and register.UpperAngle or 30
				BallSocket.Restitution = Limits["Restituition"] or 0

				BallSocket.TwistLimitsEnabled = true
				BallSocket.TwistLowerAngle = register and register.TwistLowerAngle or -60
				BallSocket.TwistUpperAngle = register and register.TwistUpperAngle or 60
				
				BallSocket.Parent = Attach1.Parent
				
			else
				local ballConstraint = obj.Parent:FindFirstChild("BallSocketConstraint")
				if ballConstraint then
					ballConstraint:Destroy()
				end
			end
			
			obj.Parent.CanCollide = isragdoll

		elseif obj.ClassName == "Motor6D" then
			if obj.Name == "Neck" then
				task.defer(function()
					obj.Enabled = not isragdoll
				end)
			else
				obj.Enabled = not isragdoll
			end
		end
	end
	
	Character.PrimaryPart.CanCollide = not isragdoll
	
	local Weld = Character.PrimaryPart:FindFirstChild("RagdollWeld")
	if not Weld then
		Weld = Instance.new("WeldConstraint")
		Weld.Name = "RagdollWeld"
		Weld.Part0 = Character.UpperTorso
		Weld.Part1 = Character.PrimaryPart
		Weld.Parent = Character.PrimaryPart
	else
		Weld:Destroy()
	end
end

function module:IsRagdoll(Humanoid)
	return Humanoid.Parent.PrimaryPart:FindFirstChild("RagdollWeld") ~= nil and Humanoid:GetState() == Enum.HumanoidStateType.Ragdoll
end

return module
