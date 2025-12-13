--[[
	-- ValueBase Utils --

	Provides methods to create appropriate ValueBase classes depending on input type.
]]

--!strict

-- Constants --
local VALUEBASE_CLASS_TYPE_LOOKUP = {
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

local TABLE_SELF_VALUE_KEY = "_self" -- You need to update ValueBaseTree type as well, as typeof reduces this singleton to the basic string type.

-- Types --
type ValueBaseLuauTypes = {
	boolean: BoolValue,
	number: NumberValue,
	string: StringValue,
	table: Folder,
}

type ValueBaseRobloxTypes = {
	BrickColor: BrickColorValue | BrickColor,
	CFrame: CFrameValue | CFrame,
	Color3: Color3Value | Color3,
	Ray: RayValue | Ray,
	Vector3: Vector3Value | Vector3,
}

type ValueBaseClassNames = {
	BoolValue: BoolValue,
	NumberValue: NumberValue,
	StringValue: StringValue,
	Folder: Folder,
	
	BrickColorValue: BrickColorValue,
	CFrameValue: CFrameValue,
	Color3Value: Color3Value,
	RayValue: RayValue,
	Vector3Value: Vector3Value,
	ObjectValue: ObjectValue,
}

-- A union of all ValueBase objects, for convenience.
export type ValueObject =
| BoolValue | NumberValue | StringValue
| BrickColorValue | CFrameValue | Color3Value
| RayValue | Vector3Value | ObjectValue

export type ValueObjectWithFolder = ValueObject | Folder

type function f_ClassFromValue(value: type, vbLuau: type, vbRoblox: type, objectValue: type)
	local vTag = value.tag
	
	-- Skip resolving if value is anytype
	if vTag == "any" then
		return value
	end
	
	-- Roblox types --
	if vTag == "class" then
		for _, rwType in vbRoblox:properties() do
			local classAndValue = rwType.read :: type
			local components = classAndValue:components()
			
			-- Check if the value of this ValueBase class matches
			if components[2] == value then
				return components[1] -- Return this ValueBase class
			end
		end
		
		-- No match, just assume it's an Instance
		return objectValue
	end
	
	-- Luau types --
	local typeSingleton = if vTag == "singleton"
		then types.singleton(type(value:value())) -- Support singletons by reducing them
		else types.singleton(vTag)

	local vbClass = vbLuau:readproperty(typeSingleton)
	
	if vbClass then
		return vbClass
	end
	
	print(`'{vTag}' is not a supported type`)
	return types.singleton(nil)
end

type function f_ClassFromTypeOf(tyof: type, vbLuau: type, vbRoblox: type, objectValue: type)
	local tTag = tyof.tag
	
	-- Skip resolving if tyof is anytype
	if tTag == "any" then
		return tyof
	end
	
	if tTag ~= "singleton" then
		if tTag == "string" then
			print([[
				The type of `f_ClassFromTypeOf` cannot be statically checked when called with a typeof string that is not statically known.
				If you'd like to use an unchecked `f_ClassFromTypeOf` call, you can cast the typeof string to `any` using `:: any`.
				
				NOTE:
				If you are encountering this message with a statically known string, it has likely been reduced to its basic type when passed through function generics.
				You can cast the typeof string as itself using `"str" :: "str"` as a workaround.
			]])
		else
			print(`f_ClassFromTypeOf expects a string singleton as the first type argument, got {tTag} instead.`)
		end
		
		return types.unknown
	end
	
	local value = tyof:value()
	local valueType = type(value)
	if valueType ~= "string" then
		print(`f_ClassFromTypeOf expects a string singleton as the first type argument, got {valueType} singleton instead.`)
		return types.unknown	
	end
	
	-- Special case, value is Instance, return ObjectValue
	if value == "Instance" then
		return objectValue
	end
	
	local valueSingleton = types.singleton(value) -- Convert to singleton so we can read it from table
	
	local vbLuauClass = vbLuau:readproperty(valueSingleton)
	if vbLuauClass then
		return vbLuauClass
	end
	
	local vbRobloxClass = vbRoblox:readproperty(valueSingleton)
	if vbRobloxClass then
		return vbRobloxClass:components()[1]
	end
	
	print(`'{value}' is not a supported type`)
	return types.singleton(nil)
end

type function f_ClassFromClassName(name: type, classes: type)
	local nTag = name.tag
	
	-- Skip resolving if name is anytype
	if nTag == "any" then
		return name
	end
	
	if nTag ~= "singleton" then
		if nTag == "string" then
			print([[
				The type of `f_ClassFromClassName` cannot be statically checked when called with a name string that is not statically known.
				If you'd like to use an unchecked `f_ClassFromClassName` call, you can cast the name string to `any` using `:: any`.
				
				NOTE:
				If you are encountering this message with a statically known string, it has likely been reduced to its basic type when passed through function generics.
				You can cast the name string as itself using `"str" :: "str"` as a workaround.
			]])
		else
			print(`f_ClassFromClassName expects a string singleton as the first type argument, got {nTag} instead.`)
		end
		
		return types.unknown
	end
	
	local value = name:value()
	local valueType = type(value)
	if valueType ~= "string" then
		print(`f_ClassFromClassName expects a string singleton as the first type argument, got {valueType} singleton instead.`)
		return types.unknown	
	end
	
	local valueSingleton = types.singleton(value) -- Convert to singleton so we can read it from table
	
	local class = classes:readproperty(valueSingleton)
	if class then
		return class
	end
	
	print(`'{value}' is not a supported class`)
	return types.unknown
end

type function f_TreeFromTable(
	data: type, tableClass: type,
	vbLuau: type, vbRoblox: type, objectValue: type,
	
	-- Used for overriding the class of the instance for tables
	-- to allow parenting to ValueBase instances directly.
	TABLE_SELF_VALUE_KEY: type
)
	local dTag = data.tag
	
	-- Skip resolving if data is anytype
	if dTag == "any" then
		return data
	end
	
	if dTag ~= "table" then
		print(`f_TreeFromTable expects a tabletype as the first type argument, got {dTag} instead.`)
		return types.unknown
	end
	
	-- Complexity protection limits
	local BUILD_DEPTH_LIMIT = 32
	local BUILD_OPERATION_LIMIT = 4096
	
	local opCount = 0
	
	-- Helper Functions --
	
	local function incrementAndCheckOpCount()
		opCount += 1

		if opCount > BUILD_OPERATION_LIMIT then
			error("f_TreeFromTable: build complexity limit exceeded (type too complex)")
		end
	end
	
	local build: (dst: type, dat: type, depth: number) -> (type)
	local buildTableValue = function(value: type, depth: number): (type)
		local selfValue = value:readproperty(TABLE_SELF_VALUE_KEY)
		if selfValue then
			value:setproperty(TABLE_SELF_VALUE_KEY) -- remove self value from type
		end

		return types.intersectionof(
			build(types.newtable(), value, depth + 1), -- recursively build
			if selfValue ~= nil
			then f_ClassFromValue(selfValue, vbLuau, vbRoblox, objectValue)
			else tableClass
		)
	end
	
	build = function(dst: type, dat: type, depth: number): (type)
		-- Recursion protection
		if depth > BUILD_DEPTH_LIMIT then
			error("f_TreeFromTable: build depth limit exceeded (type too complex)")
		end

		-- Properties
		for keyType, rwType in dat:properties() do
			incrementAndCheckOpCount()

			local value = (rwType.read or rwType.write) :: type

			if value.tag == "table" then
				dst:setproperty(keyType, buildTableValue(value, depth))
			else
				dst:setproperty(keyType, f_ClassFromValue(value, vbLuau, vbRoblox, objectValue))
			end
		end

		-- Indexer
		local indexer = dat:indexer()
		if indexer then
			incrementAndCheckOpCount()
			
			local index = indexer.index
			local value = indexer.readresult
			
			if value.tag == "table" then
				dst:setindexer(index, buildTableValue(value, depth))
			else
				dst:setindexer(index, f_ClassFromValue(value, vbLuau, vbRoblox, objectValue))
			end
		end
		
		return dst
	end
	
	-- Build and return type
	return types.intersectionof(
		build(types.newtable(), data, 0),
		tableClass
	)
end

-- User friendly types
export type ValueBaseFromValue<T> = f_ClassFromValue<
	T,
	ValueBaseLuauTypes, ValueBaseRobloxTypes, ObjectValue
>
export type ValueBaseFromTypeOf<T> = f_ClassFromTypeOf<
	T,
	ValueBaseLuauTypes, ValueBaseRobloxTypes, ObjectValue
>
export type ValueBaseTree<T, TableClass = Folder> = f_TreeFromTable<
	T, TableClass,
	ValueBaseLuauTypes, ValueBaseRobloxTypes, ObjectValue,
	"_self" -- typeof reduces this to the basic type
>
export type ValueBaseFromClassName<T> = f_ClassFromClassName<
	T,
	ValueBaseClassNames
>

-- Module --
local ValueBaseUtils = {}

--[[
	Creates a new <code>Instance</code> with the appropriate class for the given value.
	
	<code><strong>value</strong>: any</code>
	The value to create an Instance for.
	<code><strong>setValue</strong>: boolean?</code>
	Whether to set the <code>ValueBase.Value</code> to <code>value</code> if applicable.
	<strong>Default Value</strong>: <code>nil</code>
]]
local function fromValue <T>(value: T, setValue: boolean?): (ValueBaseFromValue<T>)
	local className = VALUEBASE_CLASS_TYPE_LOOKUP[typeof(value)]

	-- Not a supported type
	if not className then
		return nil :: any -- typesolver can't resolve generics here, typecast any to silence
	end

	local valueBase = Instance.new(className)
	if setValue and className ~= "Folder" then
		valueBase.Value = value
	end

	return valueBase
end

ValueBaseUtils.fromValue = fromValue

--[[
	Creates a new <code>Instance</code> with the appropriate class for the given type.
	
	<code><strong>typeOfStr</strong>: string</code>
	The type to create an Instance for.
]]
function ValueBaseUtils.fromTypeOf <T>(typeOfStr: T): (ValueBaseFromTypeOf<T>)
	local className = VALUEBASE_CLASS_TYPE_LOOKUP[typeOfStr]

	-- Not a supported type
	if not className then
		return nil :: any -- same as above
	end

	return Instance.new(className)
end

--[[
	Creates a new <code>ValueBaseTree</code> from the given <code>data</code>.

	<code><strong>data</strong>: { [string]: any }</code>
	The table to create the ValueBaseTree for.
	<code><strong>params</strong>: { [string]: any }?</code>
	The parameters to use for building the ValueBaseTree.
	
	<code><strong>dst</strong>: Instance?</code>
	The Instance to write into.
	<strong>Default Value</strong>: <code>Folder</code>
	
	<strong>[ Parameters ]</strong>
	<strong>Note:</strong> Callbacks are not considered in the resultant type.
	
	<code><strong>SetValues</strong>: boolean?</code>
	Whether to set the <code>ValueBase.Value</code> to the given value if applicable.
	<strong>Default Value</strong>: <code>nil</code>
	
	<code><strong>ShouldBuildCallback</strong>: ((value: any, sourceTable: {[string]: any}, key: string) -> (boolean))?</code>
	Callback used for determining what key-value pairs should be built for.
	<strong>Default Value</strong>: <code>nil</code>
	
	<code><strong>OnBuildCallback</strong>: ((instance: Instance, sourceTable: {[string]: any}, key: string) -> ())?</code>
	Callback that is called after each Instance creation.
	<strong>Default Value</strong>: <code>nil</code>
]]
local function writeValueBaseTree <T, TableClass>(
	data: T,
	dst: Instance?,
	params: {
		SetValues: boolean?,
		
		ShouldBuildCallback: ((value: any, sourceTable: {[string]: any}, key: string) -> (boolean))?,
		OnBuildCallback: ((instance: ValueObjectWithFolder, value: any, sourceTable: {[string]: any}, key: string) -> ())?
	}?
): (ValueBaseTree<T>)
	local parent = dst or Instance.new("Folder")
	local setValues = params and params.SetValues
	local shouldBuildCallback = params and params.ShouldBuildCallback
	local onBuildCallback = params and params.OnBuildCallback
	
	for key, value in data :: {[string]: any} do
		-- Ignore override key
		if key == TABLE_SELF_VALUE_KEY then
			continue
		end
		
		-- Call shouldBuildCallback to determine if this key-value pair should be built
		if shouldBuildCallback and not shouldBuildCallback(value, data, key) then
			continue
		end

		local valueType = typeof(value)
		local valueInstance = parent:FindFirstChild(key)

		-- Instance doesn't exist, or isn't the correct class
		if not valueInstance or not valueInstance:IsA(VALUEBASE_CLASS_TYPE_LOOKUP[valueType]) then
			if valueType == "table" then
				local overrideValue = value[TABLE_SELF_VALUE_KEY]
				if overrideValue then
					valueInstance = fromValue(overrideValue, setValues)
				else
					valueInstance = Instance.new("Folder")
				end
			else
				valueInstance = fromValue(value, setValues)
			end

			-- Check if valueInstance failed to create
			if not valueInstance then
				warn(`Failed to create value instance for {value}!`)
				continue
			end

			valueInstance.Name = key
			valueInstance.Parent = parent
		end

		if valueType == "table" then
			writeValueBaseTree(value, valueInstance, params) -- Recursively create instances
		elseif setValues then
			valueInstance.Value = value
		end

		-- Call onBuild callback
		if onBuildCallback then
			onBuildCallback(valueInstance, value, data, key)
		end
	end

	return parent :: any
end

ValueBaseUtils.writeValueBaseTree = writeValueBaseTree

--[[
	Reads a data table from the given <code>ValueBaseTree</code>, writing into <code>dst</code> if specified.
	Returns <code>dst</code>.
]]
local function readValueBaseTree <K, V>(dataTree: Instance, dst: {[K]: V}?): ({[K]: V} & {[string]: any})
	dst = dst or {}

	for _, child in dataTree:GetChildren() do
		local isValueBase = child:IsA("ValueBase")
		local isFolder = not isValueBase and child:IsA("Folder")

		-- Ignore non-ValueBase or Folder instances
		if not isValueBase and not isFolder then
			continue
		end

		local descendant = isFolder or (child:FindFirstChildWhichIsA("ValueBase") or child:FindFirstChildWhichIsA("Folder"))
		if descendant then
			local childName = child.Name
			local passDst = dst[childName] :: {[string]: any}

			if not passDst then
				passDst = {} :: {[string]: any}
				dst[childName] = passDst
			end

			if isValueBase then
				passDst[TABLE_SELF_VALUE_KEY] = (child :: any).Value
			end

			-- Recursively read
			readValueBaseTree(child, passDst)
		else
			dst[child.Name] = (child :: any).Value
		end
	end

	return dst
end

ValueBaseUtils.readValueBaseTree = readValueBaseTree

return ValueBaseUtils
