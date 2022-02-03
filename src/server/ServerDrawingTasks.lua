local Common = game:GetService("ReplicatedStorage").MetaBoardCommon
local DrawingTask = require(Common.DrawingTask)
local Config = require(Common.Config)
local LineInfo = require(Common.LineInfo)
local MetaBoard

local function resizePart(part, normal, delta)
	local axis = Vector3.FromNormalId(normal)
	part.Size = part.Size + Vector3.new(math.abs(axis.X), math.abs(axis.Y), math.abs(axis.Z)) * delta
	part.CFrame = part.CFrame * CFrame.new(axis * (delta/2))
end

local function faceAlignParts(part1, part2)
	local normalA = part1.CFrame:VectorToWorldSpace(Vector3.FromNormalId(Enum.NormalId.Left))
	local normalB = part2.CFrame:VectorToWorldSpace(Vector3.FromNormalId(Enum.NormalId.Right))
	local cross = part1.CFrame:VectorToWorldSpace(Vector3.FromNormalId(Enum.NormalId.Front))

	local extendPointA, extendPointB

	if normalA:Dot(normalB) > 0 then
		extendPointA = part1.CFrame * Vector3.new(-part1.Size.X / 2, 0, 0)
		extendPointB = part2.CFrame * Vector3.new(part2.Size.X / 2, 0, 0)
	elseif (normalA:Cross(normalB):Dot(cross)) > 0 then
		extendPointA = part1.CFrame * Vector3.new(-part1.Size.X / 2, part1.Size.Y / 2, 0)
		extendPointB = part2.CFrame * Vector3.new(part2.Size.X / 2, part2.Size.Y / 2, 0)
	else
		extendPointA = part1.CFrame * Vector3.new(-part1.Size.X / 2, -part1.Size.Y / 2, 0)
		extendPointB = part2.CFrame * Vector3.new(part2.Size.X / 2, -part2.Size.Y / 2, 0)
	end

	local startSep = extendPointB - extendPointA

	-- Find the closest distance between the rays (extendPointA, dirA) and (extendPointB, dirB):
	-- See: http://geomalgorithms.com/a07-_distance.html#dist3D_Segment_to_Segment
	local a, b, c, d, e = normalA:Dot(normalA), normalA:Dot(normalB), normalB:Dot(normalB), normalA:Dot(startSep), normalB:Dot(startSep)
	local denom = a*c - b*b

	-- Is this a degenerate case?
	if math.abs(denom) < 0.001 then
		-- Parts are parallel, extend faceA to faceB
		local lenA = (extendPointA - extendPointB):Dot(normalB)
		if normalA:Dot(normalB) > 0 then
			lenA = -lenA
		end
		resizePart(part1, Enum.NormalId.Left, lenA)
		return
	end

	-- Get the distances to extend by
	local lenA = -(b*e - c*d) / denom
	local lenB = -(a*e - b*d) / denom

	resizePart(part1, Enum.NormalId.Left, lenA)
	resizePart(part2, Enum.NormalId.Right, lenB)
end


local ServerDrawingTasks = {}
ServerDrawingTasks.__index = ServerDrawingTasks

function ServerDrawingTasks.Init()
	MetaBoard = require(script.Parent.MetaBoard)
end

ServerDrawingTasks.FreeHand = {}
ServerDrawingTasks.FreeHand.__index = ServerDrawingTasks.FreeHand

function ServerDrawingTasks.FreeHand.Init(board, curve, authorUserId, thicknessYScale, color, zIndex, pos)
	curve:SetAttribute("TaskType", "FreeHand")

	curve:SetAttribute("AuthorUserId", authorUserId)
	curve:SetAttribute("Color", color)
	curve:SetAttribute("ThicknessYScale", thicknessYScale)
	curve:SetAttribute("ZIndex", zIndex)

	curve:SetAttribute("CurveStop", pos)
	curve:SetAttribute("NumPoints", 1)

	local lineInfo = LineInfo.new(pos, pos, thicknessYScale, color)
	local worldLine = MetaBoard.CreateWorldLine(Config.WorldBoard.LineType, board.Canvas, lineInfo, zIndex)
	worldLine.Name = "0"
	worldLine.Parent = curve
	
	board.CurrentZIndex.Value += 1
end

function ServerDrawingTasks.FreeHand.Update(board, curve, pos)
	local lineInfo =
		LineInfo.new(
			curve:GetAttribute("CurveStop"),
			pos,
			curve:GetAttribute("ThicknessYScale"),
			curve:GetAttribute("Color"))
	
	local numPoints = curve:GetAttribute("NumPoints")

	if numPoints == 1 then
		-- The zero line is the dot that is created when the user first puts the
		-- tool down. It's a zero length line and makes non-rounded lines look gross,
		-- because they have an unrotated square at the start of the line
		local zeroLine = curve:FindFirstChild("0")
		-- We update it to be the new line, instead of a making a new line
		MetaBoard.UpdateWorldLine(Config.WorldBoard.LineType, zeroLine, board.Canvas, lineInfo, curve:GetAttribute("ZIndex"))
		zeroLine.Name = "1"

		-- Show it in case someone already erased the zero line
		MetaBoard.ShowWorldLine(Config.WorldBoard.LineType, zeroLine)
	else
		-- Draw the next line
		local worldLine = MetaBoard.CreateWorldLine(Config.WorldBoard.LineType, board.Canvas, lineInfo, curve:GetAttribute("ZIndex"))
		worldLine.Parent = curve
		worldLine.Name = tostring(numPoints)

		-- Resize with the previous line
		local prevLine = curve:FindFirstChild(tostring(numPoints - 1))
		faceAlignParts(prevLine, worldLine)
	end

	curve:SetAttribute("CurveStop", pos)
	curve:SetAttribute("NumPoints", numPoints + 1)
end

function ServerDrawingTasks.FreeHand.Finish(board, curve) end
function ServerDrawingTasks.FreeHand.Undo(board, curve) end
function ServerDrawingTasks.FreeHand.Redo(board, curve) end
function ServerDrawingTasks.FreeHand.Commit(board, curve)
	if #curve:GetChildren() == 0 then
		curve:Destroy()
	else
		curve:SetAttribute("Committed", true)
	end
end

ServerDrawingTasks.StraightLine = {}
ServerDrawingTasks.StraightLine.__index = ServerDrawingTasks.StraightLine


function ServerDrawingTasks.StraightLine.Init(board, curve, authorUserId, thicknessYScale, color, zIndex, pos)
	curve:SetAttribute("TaskType", "StraightLine")
	curve:SetAttribute("AuthorUserId", authorUserId)
	curve:SetAttribute("Color", color)
	curve:SetAttribute("ThicknessYScale", thicknessYScale)
	curve:SetAttribute("ZIndex", zIndex)

	curve:SetAttribute("CurveStart", pos)

	local lineInfo = LineInfo.new(pos, pos, thicknessYScale, color)
	local worldLine = MetaBoard.CreateWorldLine(Config.WorldBoard.LineType, board.Canvas, lineInfo, zIndex)
	worldLine.Name = "1"
	worldLine.Parent = curve
end

function ServerDrawingTasks.StraightLine.Update(board, curve, pos)
	local lineInfo =
		LineInfo.new(
			curve:GetAttribute("CurveStart"),
			pos,
			curve:GetAttribute("ThicknessYScale"),
			curve:GetAttribute("Color"))
	
	local worldLine = curve:FindFirstChild("1")
	MetaBoard.UpdateWorldLine(Config.WorldBoard.LineType, worldLine, board.Canvas, lineInfo, curve:GetAttribute("ZIndex"))
end

function ServerDrawingTasks.StraightLine.Finish(board, curve)
	local wholeLine = curve:FindFirstChild("1")
	local wholeLineInfo = LineInfo.ReadInfo(wholeLine)
	
	if wholeLineInfo.Length > Config.Drawing.LineSubdivisionLength then
		wholeLine:Destroy()

		local start = wholeLineInfo.Start
		local stop = wholeLineInfo.Stop
		local lineVector = stop - start

		local lineInfo
		for i=0, wholeLineInfo.Length/Config.Drawing.LineSubdivisionLength do
			if i == wholeLineInfo.Length/Config.Drawing.LineSubdivisionLength then
				break
			end

			local lineStop =
				if
					i+1 >= wholeLineInfo.Length/Config.Drawing.LineSubdivisionLength
				then
					wholeLineInfo.Stop
				else
					start + (i+1) * Config.Drawing.LineSubdivisionLength * lineVector.Unit

			lineInfo =
				LineInfo.new(
					start + i * Config.Drawing.LineSubdivisionLength * lineVector.Unit,
					lineStop,
					wholeLineInfo.ThicknessYScale,
					wholeLineInfo.Color)

			local worldLine = MetaBoard.CreateWorldLine(Config.WorldBoard.LineType, board.Canvas, lineInfo, curve:GetAttribute("ZIndex"))
			worldLine.Name = tostring(i+1)
			worldLine.Parent = curve
		end
	end
end

function ServerDrawingTasks.StraightLine.Undo(curve) end
function ServerDrawingTasks.StraightLine.Redo(curve) end
function ServerDrawingTasks.StraightLine.Commit(board, curve)
	if #curve:GetChildren() == 0 then
		curve:Destroy()
	else
		curve:SetAttribute("Committed", true)
	end
end

ServerDrawingTasks.Erase = {}
ServerDrawingTasks.Erase.__index = ServerDrawingTasks.Erase


function ServerDrawingTasks.Erase.CollectAndHide(board, erasedCurves, pos, radius)
	local linesSeen = 0

	for _, curve in ipairs(board.Canvas.Curves:GetChildren()) do
		
		local erasedLineNames = {}
		
		for _, worldLine in ipairs(curve:GetChildren()) do
			if linesSeen >= Config.LinesSeenBeforeWait then
				linesSeen = 0
				task.wait()
			end
			linesSeen += 1
			if worldLine:GetAttribute("Hidden") then continue end

			local lineInfo = LineInfo.ReadInfo(worldLine)
			if LineInfo.Intersects(pos, radius, lineInfo) then
				
				MetaBoard.HideWorldLine(Config.WorldBoard.LineType, worldLine)

				table.insert(erasedLineNames, worldLine.Name)
			end
		end

		if #erasedLineNames > 0 then
			local erasedCurve = erasedCurves:FindFirstChild(curve.Name)
			if erasedCurve == nil then
				erasedCurve = Instance.new("Folder")
				erasedCurve.Name = curve.Name
				erasedCurve.Parent = erasedCurves
			end

			for _, name in ipairs(erasedLineNames) do
				if erasedCurve:FindFirstChild(name) == nil then
					local nameVal = Instance.new("StringValue")
					nameVal.Name = name
					nameVal.Value = name
					nameVal.Parent = erasedCurve
				end
			end
		end

	end
end


function ServerDrawingTasks.Erase.Init(board, erasedCurves, authorUserId, thicknessYScale, pos)
	erasedCurves:SetAttribute("AuthorUserId", authorUserId)
	erasedCurves:SetAttribute("ThicknessYScale", thicknessYScale)
	erasedCurves:SetAttribute("TaskType", "Erase")

	ServerDrawingTasks.Erase.CollectAndHide(board, erasedCurves, pos, thicknessYScale/2)
end

function ServerDrawingTasks.Erase.Update(board, erasedCurves, pos)
	ServerDrawingTasks.Erase.CollectAndHide(board, erasedCurves, pos, erasedCurves:GetAttribute("ThicknessYScale")/2)
end

function ServerDrawingTasks.Erase.Finish(board, erasedCurves) end

function ServerDrawingTasks.Erase.Undo(board, erasedCurves)
	for _, erasedCurve in ipairs(erasedCurves:GetChildren()) do
		local curve = board.Canvas.Curves:FindFirstChild(erasedCurve.Name)
		-- Check if curve is there. If it's been undo'd it won't be, just ignore it.
		if curve then
			for _, erasedLineIdValue in ipairs(erasedCurve:GetChildren()) do
				local worldLine = curve:FindFirstChild(erasedLineIdValue.Value)
				MetaBoard.ShowWorldLine(Config.WorldBoard.LineType, worldLine)
			end
		end
	end
end

function ServerDrawingTasks.Erase.Redo(board, erasedCurves)
	for _, erasedCurve in ipairs(erasedCurves:GetChildren()) do
		local curve = board.Canvas.Curves:FindFirstChild(erasedCurve.Name)
		-- Check if curve is there. If it's been undo'd it won't be, just ignore it.
		if curve then
			for _, erasedLineIdValue in ipairs(erasedCurve:GetChildren()) do
				local worldLine = curve:FindFirstChild(erasedLineIdValue.Value)
				MetaBoard.HideWorldLine(Config.WorldBoard.LineType, worldLine)
			end
		end
	end
end

-- Destroy all of the lines which were temporarily invisible.
function ServerDrawingTasks.Erase.Commit(board, erasedCurves)
	for _, erasedCurve in ipairs(erasedCurves:GetChildren()) do
		local curve = board.Canvas.Curves:FindFirstChild(erasedCurve.Name)
		-- Check if curve is there. If it's been undo'd it won't be, just ignore it.
		-- This is kinda bad. Since those invisible lines will never get destroyed
		-- if their author redo's the curve. Doesn't seem like a huge problem.
		if curve then
			for _, erasedLineIdValue in ipairs(erasedCurve:GetChildren()) do
				local worldLine = curve:FindFirstChild(erasedLineIdValue.Value)
				worldLine:Destroy()
			end

			-- If the curve has been committed and all of it's lines were destroyed, then destroy it
			if curve:GetAttribute("Committed") and #erasedCurve:GetChildren() == 0 then
				curve:Destroy()
			end
		end
	end

	erasedCurves:Destroy()
end


return ServerDrawingTasks