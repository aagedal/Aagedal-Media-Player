-- SPDX-License-Identifier: GPL-3.0-or-later
-- Read-only Resolve console helper. Returns a function accepting a NEW JSON path.
-- Captures actual timeline markers and V1 media; never imports or creates markers.
return function(outputPath)
    local resolve = Resolve()
    local project = assert(resolve:GetProjectManager():GetCurrentProject(), "No project")
    local timeline = assert(project:GetCurrentTimeline(), "No timeline")
    local function quote(value)
        return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(c)
            return string.format('\\u%04x', string.byte(c))
        end) .. '"'
    end
    local function object(values)
        local fields = {}
        for key, value in pairs(values) do
            fields[#fields + 1] = quote(key) .. ':' .. quote(value)
        end
        table.sort(fields)
        return '{' .. table.concat(fields, ',') .. '}'
    end
    local markers = {}
    for frame, marker in pairs(timeline:GetMarkers()) do
        markers[#markers + 1] = object({frame = frame, duration = marker.duration,
            color = marker.color, name = marker.name, note = marker.note})
    end
    table.sort(markers)
    local clips = {}
    for _, item in ipairs(timeline:GetItemListInTrack('video', 1) or {}) do
        local media = assert(item:GetMediaPoolItem(), "Timeline item has no media")
        local properties = media:GetClipProperty()
        clips[#clips + 1] = object({path = assert(properties['File Path']),
            fps = assert(properties['FPS']), sourceStart = assert(properties['Start TC']),
            sourceFrames = assert(properties['Frames']), startFrame = item:GetStart(),
            endFrame = item:GetEnd(), leftOffset = item:GetLeftOffset()})
    end
    local metadata = object({schemaVersion = 1, editorVersion = resolve:GetVersionString(),
        project = project:GetName(), timeline = timeline:GetName(),
        startTimecode = timeline:GetStartTimecode(), startFrame = timeline:GetStartFrame(),
        endFrame = timeline:GetEndFrame(), rate = timeline:GetSetting('timelineFrameRate'),
        dropFrame = timeline:GetSetting('timelineDropFrameTimecode'),
        videoTracks = timeline:GetTrackCount('video')})
    local existing = io.open(outputPath, 'r')
    if existing then existing:close(); error('Refusing to overwrite evidence') end
    local output = assert(io.open(outputPath, 'w'))
    assert(output:write('{"metadata":', metadata, ',"clips":[', table.concat(clips, ','),
        '],"markers":[', table.concat(markers, ','), ']}\n'))
    assert(output:close())
    print('Saved read-only timeline snapshot: ' .. outputPath)
end
