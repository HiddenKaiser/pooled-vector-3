--!optimize 2

local INIT_VECTOR_AM = 10 -- how many vectors to preallocate
local ORGANIZE_FREE = false -- whether to keep the free vectors in order or not

local REAL_VECTOR3 = Vector3

-- Vector3's are identified with a number, and are stored in VectorRegistry array
-- This number is called the VectorId, or vId
-- Vector data is pooled when possible
-- The data is freed when the Vector3 is no longer needed, using a binary search for efficient placement
local Vector3 = {
    VectorRegistry = table.create(INIT_VECTOR_AM * 3, 0),

    freeVectors = {1}, -- first element, and every VectorId after, is free
    numFreeVectors = INIT_VECTOR_AM,
    numVectorsInRegistry = INIT_VECTOR_AM,
}
local CURSOR_CACHE = {} :: {[number]: number} -- cache for getCursor, to speed things up at the expense of memory
local DO_CACHE = true and INIT_VECTOR_AM <= 1000 -- whether to cache the cursor or not

-- Finds the index of the closest element in the array that is also less than the target in O(log n) time
-- implemented to efficiently free vectors in order, when ORGANIZE_FREE is true
-- formulated by HiddenKaiser
-- O(log n)
local function _closestBinarySearchFloored(arr: {number}, target: number): number
    local left, right, mid = 1, #arr, 0
    if right < 1 or arr[left] >= target then return 1 end  -- empty array or target is less than all elements
    if arr[right] <= target then return right end -- target is greater than all elements

    while left < right do
        mid = (left + right) // 2
        if arr[mid] < target+1 then
            left = mid + 1
        else
            right = mid
        end
    end
    return left-1
end

-- gets the cursor for the VectorId; with caching if enabled
local getCursor : (number) -> number
if DO_CACHE then
    getCursor = function(vId: number): number
        local cursor = CURSOR_CACHE[vId]
        if cursor then  return cursor  end
        --if not vId then error("No VectorId provided", 2) end
        cursor = (vId - 1) * 3 + 1
        CURSOR_CACHE[vId] = cursor
        return cursor
    end
else
    getCursor = function(vId: number): number
        return (vId - 1) * 3 + 1
    end
end

-- allocate a new vector
function Vector3.new(x: number?, y: number?, z: number?) : number

    -- allocate a new vector
    if Vector3.numFreeVectors <= 0 then
        Vector3.numVectorsInRegistry += 1
        table.insert(Vector3.VectorRegistry, x or 0)
        table.insert(Vector3.VectorRegistry, y or 0)
        table.insert(Vector3.VectorRegistry, z or 0)
        return Vector3.numVectorsInRegistry -- vId
    end

    local vId
    if #Vector3.freeVectors > 1 or Vector3.freeVectors[1] >= Vector3.numVectorsInRegistry then -- Vector3.numFreeVectors > 1
        -- if there are multiple free vectors, or the first free vector is the last in the registry, remove the last free vector
        vId = table.remove(Vector3.freeVectors, Vector3.numFreeVectors)
        Vector3.numFreeVectors -= 1
    else
        vId = Vector3.freeVectors[1]
        Vector3.freeVectors[1] += 1
    end

    local cursor = getCursor(vId)
    Vector3.VectorRegistry[cursor] = x or 0
    Vector3.VectorRegistry[cursor + 1] = y or 0
    Vector3.VectorRegistry[cursor + 2] = z or 0

    return vId
end

-- free up an existing vector to be reused
function Vector3.free(vId: number)
    if vId < 1 or vId > Vector3.numVectorsInRegistry then  error(`Vector3.free({vId}: vId out of bounds`, 2)  end

    local cursor = getCursor(vId)
    Vector3.VectorRegistry[cursor] = 0
    Vector3.VectorRegistry[cursor + 1] = 0
    Vector3.VectorRegistry[cursor + 2] = 0

    -- if organize is enabled, insert the free vector in the correct position, otherwise just append it
    -- if we need to descend the first free vector, do so
    local closeLow =
        ORGANIZE_FREE and _closestBinarySearchFloored(Vector3.freeVectors, vId)
        or (Vector3.numFreeVectors+1)
    
    -- replace the first free vector if needed
    if (Vector3.numFreeVectors > 0 and Vector3.freeVectors[1] == vId+1) then
        Vector3.freeVectors[1] = vId
    else
        table.insert(Vector3.freeVectors, closeLow)
    end
    Vector3.numFreeVectors += 1
end


-- vector math functions
function Vector3.getXYZ(vId: number): (number, number, number)
    local cursor = getCursor(vId)
    return Vector3.VectorRegistry[cursor], Vector3.VectorRegistry[cursor + 1], Vector3.VectorRegistry[cursor + 2]
end

function Vector3.magnitude(vId: number): number
    local x, y, z = Vector3.getXYZ(vId)
    return math.sqrt(x*x + y*y + z*z)
end
Vector3.size = Vector3.magnitude -- alias

-- equivalent to Vector3.unit
-- calculates magnitude internally to avoid repeated calculations
function Vector3.normalize(vId: number): ()
    local cursor = getCursor(vId)
    local x, y, z = Vector3.VectorRegistry[cursor], Vector3.VectorRegistry[cursor + 1], Vector3.VectorRegistry[cursor + 2]
    local mag = math.sqrt(x*x + y*y + z*z)
    if mag <= 0 then
        error(`Vector3.normalize({vId}): magnitude is zero V3({x},{y},{z})`, 2)
    end
    Vector3.VectorRegistry[cursor] = x / mag
    Vector3.VectorRegistry[cursor + 1] = y / mag
    Vector3.VectorRegistry[cursor + 2] = z / mag
end
Vector3.unit = Vector3.normalize -- alias

function Vector3.normalizeWithSize(vId: number, mag: number): ()
    local cursor = getCursor(vId)
    local x, y, z = Vector3.VectorRegistry[cursor], Vector3.VectorRegistry[cursor + 1], Vector3.VectorRegistry[cursor + 2]
    Vector3.VectorRegistry[cursor] = x / mag
    Vector3.VectorRegistry[cursor + 1] = y / mag
    Vector3.VectorRegistry[cursor + 2] = z / mag
end

-- converts to a new Roblox Vector3 object
function Vector3.toRealVector3(vId: number): Vector3
    return REAL_VECTOR3.new(Vector3.getXYZ(vId))
end
function Vector3.toString(vId: number)
    local x, y, z = Vector3.getXYZ(vId)
    return `Vector3_F({x}, {y}, {z})`
end
function Vector3.print(vId: number)
    print(Vector3.toString(vId))
end


-- arithmetic operations
function Vector3.add(vId1: number, vId2: number): ()
    local cursor1 = getCursor(vId1)
    local cursor2 = getCursor(vId2)
    Vector3.VectorRegistry[cursor1] += Vector3.VectorRegistry[cursor2]
    Vector3.VectorRegistry[cursor1 + 1] += Vector3.VectorRegistry[cursor2 + 1]
    Vector3.VectorRegistry[cursor1 + 2] += Vector3.VectorRegistry[cursor2 + 2]
end

function Vector3.sub(vId1: number, vId2: number): ()
    local cursor1 = getCursor(vId1)
    local cursor2 = getCursor(vId2)
    Vector3.VectorRegistry[cursor1] -= Vector3.VectorRegistry[cursor2]
    Vector3.VectorRegistry[cursor1 + 1] -= Vector3.VectorRegistry[cursor2 + 1]
    Vector3.VectorRegistry[cursor1 + 2] -= Vector3.VectorRegistry[cursor2 + 2]
end

function Vector3.mult(vId: number, scalar: number): ()
    local cursor = getCursor(vId)
    Vector3.VectorRegistry[cursor] *= scalar
    Vector3.VectorRegistry[cursor + 1] *= scalar
    Vector3.VectorRegistry[cursor + 2] *= scalar
end

function Vector3.div(vId: number, scalar: number): ()
    local cursor = getCursor(vId)
    Vector3.VectorRegistry[cursor] /= scalar
    Vector3.VectorRegistry[cursor + 1] /= scalar
    Vector3.VectorRegistry[cursor + 2] /= scalar
end

function Vector3.floordiv(vId: number, scalar: number): ()
    local cursor = getCursor(vId)
    Vector3.VectorRegistry[cursor] //= scalar
    Vector3.VectorRegistry[cursor + 1] //= scalar
    Vector3.VectorRegistry[cursor + 2] //= scalar
end

function Vector3.dot(vId1: number, vId2: number): number
    local cursor1 = getCursor(vId1)
    local cursor2 = getCursor(vId2)
    return Vector3.VectorRegistry[cursor1] * Vector3.VectorRegistry[cursor2] +
           Vector3.VectorRegistry[cursor1 + 1] * Vector3.VectorRegistry[cursor2 + 1] +
           Vector3.VectorRegistry[cursor1 + 2] * Vector3.VectorRegistry[cursor2 + 2]
end

function Vector3.cross(vId1: number, vId2: number): ()
    local cursor1 = getCursor(vId1)
    local cursor2 = getCursor(vId2)
    local x1, y1, z1 = Vector3.VectorRegistry[cursor1], Vector3.VectorRegistry[cursor1 + 1], Vector3.VectorRegistry[cursor1 + 2]
    local x2, y2, z2 = Vector3.VectorRegistry[cursor2], Vector3.VectorRegistry[cursor2 + 1], Vector3.VectorRegistry[cursor2 + 2]
    Vector3.VectorRegistry[cursor1] = y1 * z2 - z1 * y2
    Vector3.VectorRegistry[cursor1 + 1] = z1 * x2 - x1 * z2
    Vector3.VectorRegistry[cursor1 + 2] = x1 * y2 - y1 * x2
end


function Vector3.set(vId: number, x: number, y: number, z: number): ()
    local cursor = getCursor(vId)
    Vector3.VectorRegistry[cursor] = x
    Vector3.VectorRegistry[cursor + 1] = y
    Vector3.VectorRegistry[cursor + 2] = z
end

function Vector3.copy(vId1: number, vId2: number): ()
    local cursor1 = getCursor(vId1)
    local cursor2 = getCursor(vId2)
    Vector3.VectorRegistry[cursor1] = Vector3.VectorRegistry[cursor2]
    Vector3.VectorRegistry[cursor1 + 1] = Vector3.VectorRegistry[cursor2 + 1]
    Vector3.VectorRegistry[cursor1 + 2] = Vector3.VectorRegistry[cursor2 + 2]
end


-- zero and one
function Vector3.zero(): number
    return Vector3.new(0, 0, 0)
end
function Vector3.one(): number
    return Vector3.new(1, 1, 1)
end

-- axises
function Vector3.xAxis(): number
    return Vector3.new(1,0,0)
end
function Vector3.yAxis(): number
    return Vector3.new(0,1,0)
end
function Vector3.zAxis(): number
    return Vector3.new(0,0,1)
end

function Vector3.clamp(vId: number, min: number, max: number): number
    local cursor = getCursor(vId)
    local x, y, z = Vector3.VectorRegistry[cursor], Vector3.VectorRegistry[cursor + 1], Vector3.VectorRegistry[cursor + 2]
    x = math.clamp(x, min, max)
    y = math.clamp(y, min, max)
    z = math.clamp(z, min, max)
    Vector3.VectorRegistry[cursor] = x
    Vector3.VectorRegistry[cursor + 1] = y
    Vector3.VectorRegistry[cursor + 2] = z
    return vId
end

return Vector3
