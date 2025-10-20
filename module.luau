--[[
	-- ValueBase Utils --

	Provides methods to create appropriate ValueBase classes depending on input type.
]]

--!strict

local VALUEBASE_CLASSTYPE_LOOKUP = {
	boolean = "BoolValue",
	number = "NumberValue",
	string = "StringValue",
	table = "Folder",
	
	BrickColor = "BrickColorValue",
	CFrame = "CFrameValue",
	Color3 = "Color3Value",
	Ray = "RayValue",
	Vector3 = "Vector3Value",
	Instance = "ObjectValue",
}

type ValueBaseClasses = {
	boolean: BoolValue,
	number: NumberValue,
	string: StringValue,
	table: Folder,
}

type ValueBaseRobloxClasses = {
	BrickColor: BrickColorValue | BrickColor,
	CFrame: CFrameValue | CFrame,
	Color3: Color3Value | Color3,
	Ray: RayValue | Ray,
	Vector3: Vector3Value | Vector3,
	Instance: ObjectValue,
}

-- Module --
local ValueBaseUtils = {}

type function funcValueBaseFromValueType(basicClasses: type, robloxClasses: type, value: type)
	-- Skip refinement if v is any
	if value:is("any") then
		return types.any
	end
	
	-- Check if v is a classtype
	if value:is("class") then
		for _, rwValue in robloxClasses:properties() do
			local class = rwValue.read :: type
			
			if not class:is("union") then
				continue
			end
			
			local components = class:components()
			if components[2] == value then
				return components[1]
			end
		end
		
		-- couldn't find a match, just assume it's an instance
		return robloxClasses:readproperty(types.singleton("Instance")) or types.unknown
	end
	
	-- Support v singletons (literals) by reducing them to their basic type
	local basicType = if value:is("singleton")
		then types.singleton(type(value:value()))
		else types.singleton(value.tag)
	
	local class = basicClasses:readproperty(basicType) or robloxClasses:readproperty(basicType)
	if not class then
		print(`{value.tag} is not a supported type`)
		return types.singleton(nil)
	end

	return class
end

export type ValueBaseFromValueType<T> = funcValueBaseFromValueType<ValueBaseClasses, ValueBaseRobloxClasses, T>

--[[
	Creates a new <code>ValueBase</code> or <code>Folder</code> Instance with the appropriate class for the given value.
]]
local function newValueBaseFromValue <T>(value: T, setValue: boolean?): (ValueBaseFromValueType<T>)
	local valueType = typeof(value)
	local className = VALUEBASE_CLASSTYPE_LOOKUP[valueType]
	
	if not className then
		return nil :: any -- typesolver cant resolve T here so it thinks it's `never`, typecast any to silence
	end
	
	local valueBase = Instance.new(className)
	
	if setValue and valueBase:IsA("ValueBase") then
		valueBase.Value = value
	end
	
	return valueBase
end

ValueBaseUtils.newValueBaseFromValue = newValueBaseFromValue

type function funcValueBaseFromTypeOfString(basicClasses: type, robloxClasses: type, value: type)
	local SOURCE_STR = "ValueBaseFromTypeString<basicClasses, robloxClasses, value>"

	if not value:is("singleton") then
		print(
			`{SOURCE_STR} expects a string singleton as the second type argument, got {value.tag} instead.{
			if value:is("string")
				then " If you have passed a string literal, it has likely been reduced to the basic type when passed through the function generic, typecast the string literal as itself to fix this error."
				else ""
			}`
		)
		
		if value:is("string") then
			return types.unknown
		end
		
		return types.singleton(nil)
	end

	local vValue = value:value()
	if type(vValue) ~= "string" then
		print(`{SOURCE_STR} expects a string singleton as the second type argument, got {type(vValue)} singleton instead`)
		return types.singleton(nil)
	end

	local vValueSingleton = types.singleton(vValue)
	local class = basicClasses:readproperty(vValueSingleton) or robloxClasses:readproperty(vValueSingleton)
	
	if not class then
		print(`{vValue} is not a supported type`)
		return types.singleton(nil)
	end
	
	if class:is("union") then
		return class:components()[1]
	end

	return class
end

export type ValueBaseFromTypeOfString<T> = funcValueBaseFromTypeOfString<ValueBaseClasses, ValueBaseRobloxClasses, T>

--[[
	Creates a new <code>ValueBase</code> or <code>Folder</code> Instance with the appropriate class for the given type.

	<strong>Note</strong>: You must typecast the given typeOfStr as the string literal to avoid type errors.
]]
local function newValueBaseFromTypeOf <T>(typeOfStr: T): (ValueBaseFromTypeOfString<T>)
	local className = VALUEBASE_CLASSTYPE_LOOKUP[typeOfStr]
	
	if not className then
		return nil :: any -- typesolver cant resolve T here so it thinks it's `never`, typecast any to silence
	end
	
	return Instance.new(className)
end

ValueBaseUtils.newValueBaseFromTypeOf = newValueBaseFromTypeOf

--[[
	Reads a data table from the given <code>ValueBaseTree</code>, writing into <code>dst</code> if specified.

	Returns <code>dst</code>.
]]
local function readValueBaseTree <K, V>(dataTree: Instance, dst: {[K]: V}?): ({[K]: V} & {[string]: any})
	dst = dst or {}

	for _, child in dataTree:GetChildren() do
		if child:IsA("ValueBase") then
			dst[child.Name] = (child :: any).Value
		elseif child:IsA("Folder") then
			local childName = child.Name
			local passDst = dst[childName]

			if not passDst then
				passDst = {}
				dst[childName] = passDst
			end

			-- Recursively read
			readValueBaseTree(child, passDst)
		end
	end

	return dst
end

ValueBaseUtils.readValueBaseTree = readValueBaseTree

type function funcTableToInstanceTree(t: type, folderClass: type)
	local SOURCE_STR = "TableToInstanceTree<t, folderClass>"
	
	if not t:is("table") then
		print(`{SOURCE_STR} expects a tabletype as the second type argument, got {t.tag} instead`)
		return types.unknown
	end
	
	local function build(dst: type, data: type)
		for keyType, rwValue in data:properties() do
			local valueType = (rwValue.read or rwValue.write) :: type
			
			if not valueType:is("table") then
				dst:setproperty(keyType, ValueBaseFromValueType(valueType))
				continue
			end
			
			-- recursively build
			local subDst = build(types.newtable(), valueType)
			dst:setproperty(keyType, types.intersectionof(subDst, folderClass))
		end
		
		return dst
	end
	
	return types.intersectionof(build(types.newtable(), t), folderClass)
end

export type ValueBaseTree<T> = funcTableToInstanceTree<T, Instance>

--[[
	Writes a <code>ValueBaseTree</code> from the given data table, writing into <code>parent</code> if specified.
]]
local function writeValueBaseTree <T>(data: T, parent: Instance?, setValues: boolean?, callback: (instance: Instance, sourceTable: {[string]: any}, key: string) -> ()?): ValueBaseTree<T>
	parent = parent or Instance.new("Folder")
	
	for key, value in data :: {[string]: any} do
		local valueType = type(value)
		local valueInstance = parent:FindFirstChild(key)
		
		if not valueInstance then
			valueInstance = newValueBaseFromValue(value :: any)
			
			-- check if valueInstance failed to create
			if not valueInstance then
				warn(`Failed to create value instance for {value}!`)
				
				continue
			end
			
			valueInstance.Name = key
			valueInstance.Parent = parent
		end
		
		if callback then
			callback(valueInstance, data, key)
		end

		if valueType == "table" then
			-- Recursively create instances
			(writeValueBaseTree :: any)(value, valueInstance, setValues, callback)
		elseif setValues then
			(valueInstance :: any).Value = value
		end
	end
	
	return parent :: any
end

ValueBaseUtils.writeValueBaseTree = writeValueBaseTree

return ValueBaseUtils
