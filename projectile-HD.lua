-- strict!
local RunService = game:GetService("RunService") --2
local HTTPService = game:GetService("HttpService") --3 
local ReplicatedStorage = game:GetService("ReplicatedStorage") --4
local Debris = game:GetService("Debris") --5

local MINIMUM_VELOCITY = 3 --6
local MAX_BOUNCES = 5 --7
local DEFAULT_VELOCITY_SCALE = 0.5 

local cast = ReplicatedStorage.Cast 

local Projectile = {} 
Projectile.RunningProjectile = {} 

Projectile.__index = Projectile -- we use .__index so that lua will find missing behaviors and values that are missing in our instance --12


-- declaring the projectile instance type
-- this makes sure that, the new mortar instances we create follows the behavior
-- and structure of that is defined by the Mortar metatable
-- this is important becs it enforces strict type checking on the instances created
-- and also it allows for autocomplete and can warn us if the instance type does not
-- match the type declaration
type ProjectileClass  = typeof(setmetatable( 

	{} :: {

		-- configs
		ProjectileId : string ; -- the id of the projectile
		Projectile : BasePart ; -- the projectile object
		Gravity : number ; -- gravity multiplier // how much gravity affects the projetile
		LifeTime : number ; -- how long the projectile can exist
		BlackList : {BasePart} | {Model} ;
		Speed : number ; -- how fast the projectile is moving?
		Debug : boolean ; -- turn on/off debug
		HitboxSize : Vector3 ; -- size of the hitbox -- > to detect players inside hitbox to apply damage and/or knockback effects
		Damage : number ; -- damage the projectile does
		HitCharacters : {Model}? ; -- list of characters that are already damaged by projectile
		Bounce : boolean ; -- to check if the projectile is supposed to bounce or not
		Damping : number ; -- percentage of velocity lost each bounce --> so projectile dont bounce forever
		ExplosionTime : number ; -- time it takes for the explosion to happen
		VelocityScale : number ; -- velocity scale to slow or speed up projectile
		KnockbackEnabled : boolean ; -- determines whether or not to apply knockback
		ExplosionImpact : number ; -- impact of the explosion
		SpinEnabled : boolean ; -- whether or not to make the projectile spin

	}, 

	Projectile -- 24
	))

-- constructor returns a new instance of the projectile class
-- this is used to create new projectiles
function Projectile.new(
projectile : BasePart ,gravity : number , lifeTime : number , blackList : {BasePart} | {Model} , speed : number ,
debugBool : boolean , hitboxSize : Vector3 , damage : number , bounce : boolean , damping : number , explosionTime : number
, velocityScale : number ,knockbackEnabled : boolean, explosionImpact : number , spinBool : boolean ) : ProjectileClass

	local self : ProjectileClass = {
		-- assigning the type definitions from the Projectile class we created to the new projectile instance
		-- this makes sure our new instance follows the structure of the Projectile class

		-- configs
		ProjectileId = HTTPService:GenerateGUID(false) ; -- generates id to identify projectile 
		Projectile = projectile ;
		Gravity = gravity ;
		LifeTime = lifeTime ;
		BlackList = blackList ;
		Speed = speed ; 
		Debug = debugBool;
		HitboxSize = hitboxSize ; 
		Damage = damage ; 
		HitCharacters = {} ;
		Bounce = bounce ;
		Damping = damping ;
		ExplosionTime = explosionTime ;
		VelocityScale = velocityScale ;
		KnockbackEnabled = knockbackEnabled ;
		ExplosionImpact = explosionImpact ;
		SpinEnabled = spinBool ;

	}
	-- this script tells lua to fall back to Projectile table as it's metatable 
	-- this allows lua to find any missing values and behaviors in our instance inside of the Projectile table!
	setmetatable(self , Projectile)


	self:RegisterProjectile()

	return self -- self is our new projectile instance that we just created!
end

-- private functions

function Projectile:__ConfigureProjectile(projectileId : string , cast , explode)
	-- configure new projectile's cast and explode function
	-- cast and explode function 
	Projectile.RunningProjectile[projectileId] = { 
		Cast = cast ; -- this function will run when the projectile hits something
		Explode = explode ; -- this function will run when projectile is out of lifetime/exploded/touch ground
	}

end 

function Projectile.__CreateHitbox(self : ProjectileClass) : Part
	-- creates hitbox 
	local hitBox : Part = Instance.new("Part")
	hitBox.Size = self.HitboxSize
	hitBox.Transparency = 0.5
	hitBox.Anchored = true
	hitBox.CanCollide = false
	hitBox.CanQuery = false
	hitBox.CanTouch = false
	hitBox.CFrame = (CFrame.new(self.Projectile.Position + Vector3.new(0 , 2 , 0)) * CFrame.Angles(0, 0, math.rad(90)))
	hitBox.Shape = "Cylinder"
	hitBox.Parent = workspace.Ignore

	return hitBox
end


function Projectile.RegisterProjectile(self : ProjectileClass)
	-- this function will register a projectile into the RunningProjectile table and attach the projectile with
	-- this will make it easier to keep track and  manage our projectiles( for replication , clean up and vfx on other clients )

	--raycast check
	local rayResult : RaycastResult = nil
	local hit : boolean = false
	local currentNormal
	local currentPos

	self:__ConfigureProjectile(
		self.ProjectileId , 

		function (origin : Vector3  , destination : Vector3) -- cast 
			-- this function is used to cast projectile instances that we created
		
			local direction = (destination - origin).Unit -- unit vector of the direction of the projectile and magnitude of 1
			
			local initialVelocity = direction * self.Speed-- this gives us the initial velocity of the projectile --> u -- > this works because : velocity is basically just
			-- which direction something is going and how fast?
			
			
			-- the direction with magnitude of 1 will be multiplied by the Force which is in meters and it will get converted to studs
			local currentVelocity

			local acceleration = Vector3.new(0 , -workspace.Gravity * self.Gravity , 0) -- acceleration of the projectile --> a
			-- accelaration of gravity in the Y direction which is negative because it pulls the projectile downwards
			local t = 0 -- start time

			local params : RaycastParams = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude -- raycast will ignore
			params.FilterDescendantsInstances = self.BlackList -- blacklists instances so the raycast ignores 

			-- creating projectile 
			local projectileClone = self.Projectile:Clone() -- clones new projectile
			self.Projectile = projectileClone  -- sets new projectile as current projectile
			self.Projectile.CFrame = CFrame.new(origin , destination) -- sets the current CFrame of projectile
			self.Projectile.Parent = workspace.Ignore -- places projectile in a folder that's in self.BlackList so projectiles don't hit each other
			local currentPos = origin
			local bounces = 0 -- keeps track of bounces
			local timeNow = os.time() -- keeping track of the time projectile is launched into the air
			
			local spinSpeed = math.rad(math.random(360 , 540 )) -- rad per second
			
			
			local connection = RunService.Heartbeat:Connect(function(deltaTime : number)
				if not hit then
					t += deltaTime

					-- v = u + at -- another SUVAT equation
					currentVelocity = initialVelocity + acceleration * t -- this will update the current velocity each frame 

					local projectilePos = Vector3.new(
						origin.X + initialVelocity.X * t, 
						origin.Y + initialVelocity.Y * t + 0.5 * acceleration.Y * t * t,
						-- displacement = initial velocity * time + 0.5 * acceleration * time^2
						-- displacement --> the change in position -- > s 
						-- initial velocity --> the velocity at the start --> u
						-- acceleration --> the total accelaration acting on the object ---> a
						--(in our case it is the constant accelaration of gravity pulling it downward over time) 
						-- time --> the time that has elapsed since the object started moving (deltaTime -- > will be used in RunService later) --> t
						-- simplify this and we get one of the SUVAT equations to calculate the linear motion of the projectile
						-- > s = ut + 0.5 * a * t^2
						--The reason we can use this equation is because, the motion of our projectile is basically just a vertical launch from origin.Y
						-- to final Y position with a constant acceleration of gravity pulling it downwards
						-- and from that we can find the final position of Y by saying ;
						--> final Y = origin.Y + displacement
						--> final Y = origin.Y + s
						--> final Y = origin.Y + initial velocity  * deltaTime + 0.5 * accelaration * deltaTime ^ 2
						origin.Z + initialVelocity.Z * t 
						-- for the final poisition of Z and X , they are NOT affected by the accelartion of gravity ,
						-- this means their initial velocity will stay the same the whole motion.
						-- thus we can do ; final Z and final X = origin + initial velocity * time
						-- why does this work? because we take the previous equation of  s = ut + 0.5 * a * t^2 and just remove the part 
						-- that is affected by accelaration of gravity leaving us with s = ut 
					)
				
					
					
					rayResult = workspace:Raycast(currentPos , (projectilePos - currentPos) , params )
					currentPos = projectilePos
					
					
					if self.SpinEnabled then
			
						local spinDirection = (currentVelocity.Unit:Cross(Vector3.yAxis)) -- > direction of spin which is the cross product of where the projectile is heading(current velocity) and the y axis ; Vector3.new(0 , 1 , 0) which gives us 
						-- the left and right side relative to the projectile motion
						local spinAngle = spinDirection * Vector3.new(math.random(8 , 14) , 0 , 0) -- this line spinds our projectile on the local x axis looking at the spin direction we calculated
						self.Projectile.CFrame = CFrame.new(projectilePos , direction)  * CFrame.Angles(spinAngle.X , 0 , 0) -- applies spin to cframe
						-- if spin is enabled then the projectile will spin around the Y axis based on the current velocity
					else
						self.Projectile.CFrame = CFrame.new(projectilePos , direction) -- if spin is not enabled then just sets projecile current CFrame
						-- to the current projectile position based on calculation and look at the direction its going to 
					end
					
					if self.Debug then -- this is used for debugging so we can see how the projectile travels
						local part = Instance.new("Part")
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
						part.CanTouch = false
						part.Size = Vector3.new(0.5 , 0.5, 0.5)
						part.Color = Color3.new(1, 0, 0)
						part.Position = projectilePos
						part.Shape = "Ball"
						part.Transparency = 0
						part.Parent = workspace
						Debris:AddItem(part , 5)
					end

					if t >= self.LifeTime then -- if exceeds despawn time while projectile is still travelling disconnect
						hit = true

					end

					if rayResult then
						-- hit something
						-- repositioning projectile so it faces the direction it last landed
						local cf = self.Projectile.CFrame
						
						local pos = Vector3.new(cf.Position.X, self.Projectile.Size.Y / 2, cf.Position.Z) -- make sure center of projectile always above ground to avoid clipping through the ground
						
						self.Projectile.CFrame = CFrame.lookAt(pos, pos + cf.LookVector) -- makes sure projectile faces the direction it was going
			
						if self.Bounce then
							
							-- if Bounce property is true then 
							-- reflect the projectile by creating a new arc in an opposing direction
							t = 0 -- hit ground , create new arc to reflect
							bounces = bounces + 1 -- increment bounce counter everytime we bounce to check if still within the bounce limit
							if initialVelocity.Magnitude < 3 or bounces >= MAX_BOUNCES then
								self.Projectile.CanCollide = true -- enables physics 
								hit = true -- once bounce limit is reached or velocity is too low then despawn projectile
							end
							--rayResult.Normal -- > n -- > defines the surface normal which is the plane we're bouncing off
							-- currentVelocity -- > d -- > defines the direction of the projectile
							initialVelocity = (currentVelocity - ( 2 * currentVelocity:Dot(rayResult.Normal) * rayResult.Normal)) *  self.Damping -- this makes sure our projectile loses energy every time it bounce 
							-- so it does not bounce forever.
							
							-- r=d−2(d⋅n)n -- vector reflection equation where n is normalized and d*n is the dot product 
							-->  r is the reflected normal vector ( the normal of the reflected vector created from the incident vector (d) being reflected off the surface normal (n)
							-- > d is the incident vector ( direction we're going )
							--> n is the surface normal ( what we're bouncing on).
							-- > this works by giving us a new initialVelocity for a NEW projectile motion in a REFLECTED direction 
							
							origin = rayResult.Position 
							currentPos = origin
							-- reset our current position and origin to the new projectile motion that is reflected
							
						else
							hit = true -- hit something and not bouncy so stop calculating motion and disconnect
						end


					end
				end

			end)

			while not hit do
				task.wait() -- wait for hit to be true
			end

			if hit then
				connection:Disconnect()
				if self.ExplosionTime == 0 then -- if the explosion time is already zero when projectile reaches the ground , explode
					self:RemoveProjectile()
				else
					local timePassed = os.time() - timeNow -- the current time subtracted by the time projectile is launched 
					-- to get the time that has passed since projectile was launched
					
					task.delay((self.ExplosionTime - timePassed), function() -- explosion time is the time before the explosion happens
						-- after projectile is launched. we subtract this value with the time that has passed to get the remaining time
						--before explosion
						
						self:RemoveProjectile()
					end)
				end
			end
		end,

		function () -- explode function
			-- this function will handle area of effect and impact from explosion
			local hitBox : Part = self:__CreateHitbox() -- creates a hitbox

			local detected = workspace:GetPartsInPart(hitBox) -- gets all parts detected in the hitbox

			task.delay(2 , function()
				hitBox:Destroy() -- after 2 seconds , destroy the hitbox
			end)

			for _ , target in detected do
				local humanoid : Humanoid = target.Parent:FindFirstChildOfClass("Humanoid") -- makes sure the part detected has a humanoid
				-- this confirms the part belongs to a character not some random part

				if humanoid and humanoid.Health > 0  then -- humanoid exists and player is still alive
					local character : Model = humanoid.Parent -- get the character of the humanoid

					if character and not self.HitCharacters[character] then
						self.HitCharacters[character] = character -- registers player already hit by the explosion , ensures players don't get damaged multiple times
						humanoid:TakeDamage(self.Damage) -- damages player
						local rootPart : Part =  character.HumanoidRootPart
						
						if not self.KnockbackEnabled then continue end -- checks if knockback is enabled if not skips to next player
						
						if character then self:Knockback(character) end -- applies knockback to player's character
					end
				end
			end
		end
	)
end

function Projectile.Knockback(self : ProjectileClass , char : Model)
	
	local rootPart : Part = char.HumanoidRootPart
	local humanoid : Humanoid = char.Humanoid
	
	if not (rootPart and humanoid) then
		return
	end
	rootPart:SetNetworkOwner(nil) -- sets the network ownership to server so server can manipulate player's rootpart
	
	humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- change humanoid state so it can be affected by physics
	local direction = (rootPart.Position - self.Projectile.Position).Unit -- get the direction of the explosion from the player
	rootPart:ApplyImpulse((direction + Vector3.new(0 , 2 ,0)) * rootPart.AssemblyMass * self.ExplosionImpact)
	-- apply impulse to player's rootpart based on character's mass  , direction and explosion impact and Vector3.new(0 , 2 ,0))  adds a little fling to the player
	
	task.delay(4 ,  function()
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) -- change humanoid state back to normal which is not affected by physics
		-- allows player to recover from falling
		
		rootPart:SetNetworkOwnershipAuto() -- returns network ownership back to client so player is able to control rootpart again
	end
	)
end

function Projectile.RemoveProjectile(self : ProjectileClass)
	-- this function will unregister projectile once its out of range or has exploded
	-- runs a function to remove the projectile and do clean ups 
	local projectile = Projectile.RunningProjectile[self.ProjectileId]

	if not projectile then
		return
	end

	projectile.Explode()

	if self.Projectile then
		self.Projectile:Destroy()
	end

	self.HitCharacters = nil

	Projectile.RunningProjectile[self.ProjectileId] = nil -- clean up projectile from table
	--print(Projectile.RunningProjectile)
	-- this function ensures no memory leak happens
end

function Projectile.Cast(self : ProjectileClass , origin : Vector3 , destination : Vector3)
	local projectile = Projectile.RunningProjectile[self.ProjectileId] -- checking if projectile really exists
	-- to prevent errors and more security

	if not projectile then
		return
	end
	
	--print(Projectile.RunningProjectile)
	projectile.Cast(origin , destination) -- this function will cast the projectile instance we created based on origin (tool handle's position) and destination  (our mouse.Hit)
end

return Projectile
