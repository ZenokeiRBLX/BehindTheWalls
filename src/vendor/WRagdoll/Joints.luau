--[[

	This module is a configuration for the main "Wo's Ragdoll" module!
	Here, you can modify each body joint's malleability on Ragdoll mode

]]

local mft1, mft2, mft3 = 0, 0, 20
local ua1, ua2, ua3 = 100, 40, 5
local tla1, tla2, tla3 = -45, -20, -10
local tua1, tua2, tua3 = 45, 20, 10

local Limits = {
	Restituition = .93,

	RightShoulderRigAttachment = {
		MaxFrictionTorque = mft1,
		UpperAngle = ua1,
		TwistLowerAngle = tla1,
		TwistUpperAngle = tua1,
	},

	RightElbowRigAttachment = {
		MaxFrictionTorque = mft2,
		UpperAngle = ua2,
		TwistLowerAngle = tla2,
		TwistUpperAngle = tua2,
	},

	RightWristRigAttachment = {
		MaxFrictionTorque = mft3,
		UpperAngle = ua3,
		TwistLowerAngle = tla3,
		TwistUpperAngle = tua3,
	},

	LeftShoulderRigAttachment = {
		MaxFrictionTorque = mft1,
		UpperAngle = ua1,
		TwistLowerAngle = tla1,
		TwistUpperAngle = tua1,
	},

	LeftElbowRigAttachment = {
		MaxFrictionTorque = mft2,
		UpperAngle = ua2,
		TwistLowerAngle = tla2,
		TwistUpperAngle = tua2,
	},

	LeftWristRigAttachment = {
		MaxFrictionTorque = mft3,
		UpperAngle = ua3,
		TwistLowerAngle = tla3,
		TwistUpperAngle = tua3,
	},

	RightHipRigAttachment = {
		MaxFrictionTorque = mft1,
		UpperAngle = ua1,
		TwistLowerAngle = tla1,
		TwistUpperAngle = tua1,
	},

	RightKneeRigAttachment = {
		MaxFrictionTorque = mft2,
		UpperAngle = ua2,
		TwistLowerAngle = tla2,
		TwistUpperAngle = tua2,
	},

	RightAnkleRigAttachment = {
		MaxFrictionTorque = mft3,
		UpperAngle = ua3,
		TwistLowerAngle = tla3,
		TwistUpperAngle = tua3,
	},

	LeftHipRigAttachment = {
		MaxFrictionTorque = mft1,
		UpperAngle = ua1,
		TwistLowerAngle = tla1,
		TwistUpperAngle = tua1,
	},

	LeftKneeRigAttachment = {
		MaxFrictionTorque = mft2,
		UpperAngle = ua2,
		TwistLowerAngle = tla2,
		TwistUpperAngle = tua2,
	},

	LeftAnkleRigAttachment = {
		MaxFrictionTorque = mft3,
		UpperAngle = ua3,
		TwistLowerAngle = tla3,
		TwistUpperAngle = tua3,
	},

	NeckRigAttachment = {
		MaxFrictionTorque = 0,
		UpperAngle = 15,
		TwistLowerAngle = -50,
		TwistUpperAngle = 50,
	},
}

return Limits
