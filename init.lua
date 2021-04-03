local root_obj_ptr = 0x00aca2e4
local known_vtable_names = {
    [0x00b47a80] = "RootType1",
    [0x00b47a90] = "RootType2",
    [0x00b39460] = "Player",
    [0x00b45c50] = "LobbyMenuHandler",
    [0x00b47228] = "UnknownUDPHandler",
    [0x00b471a8] = "ReceivedPacketsHandler",
    [0x00b45c60] = "IdleDisconnectHandler",
    [0x00b3f9b8] = "UnknownAnimationCounterUpdater"
}

local function get_vtable_ptr(obj_ptr)
    return pso.read_u32(obj_ptr)
end

local function get_class_name(obj_ptr)
    local vtable_ptr = get_vtable_ptr(obj_ptr)

    for addr, name in pairs(known_vtable_names) do
        if addr == vtable_ptr then
            return name
        end
    end

    return "UnknownClass"
end

local function parse_pso_base_object(obj_ptr)
    local name = get_class_name(obj_ptr)
    local vtable_ptr = get_vtable_ptr(obj_ptr)
    local flags1 = pso.read_u16(obj_ptr + 8)
    local flags2 = pso.read_u32(obj_ptr + 0x1c)
    local data_ptr = pso.read_u32(obj_ptr + 4)

    local friend_object_ptrs = {}
    local first_friend_ptr = obj_ptr + 0xc
    local last_fiend_ptr = obj_ptr + 0x18
    for i = first_friend_ptr, last_fiend_ptr, 4 do
        table.insert(friend_object_ptrs, pso.read_u32(i))
    end

    return {
        address = obj_ptr,
        name = name,
        vtable_ptr = vtable_ptr,
        flags1 = flags1,
        flags2 = flags2,
        data_ptr = data_ptr,
        friend_object_ptrs = friend_object_ptrs
    }
end

local function null_ptr(ptr)
    return ptr == 0
end

local indent_width = 10
local max_depth = 10000

local lowest_depth = 0
local too_deep = false
local has_self_refs = false
local has_circular_refs = false

local function visualize_object_hierarchy(title, obj_ptr, visited, depth)
    local obj = parse_pso_base_object(obj_ptr)

    if depth > max_depth then
        imgui.Text(string.format("%s: Max depth", title))
        return
    end

    local is_visited = false
    for i = 1, #visited do
        if visited[i] == obj_ptr then
            is_visited = true
            break
        end
    end

    local text = string.format("%s: \"%s\" (%08x, %04x, %08x, %08x, %08x)", title, obj.name, obj.data_ptr, obj.flags1, obj.flags1, obj.address, obj.vtable_ptr)
    if is_visited then
        text = text .. " [CYCLE]"
    else
        table.insert(visited, obj_ptr)
    end

    local fake_indent = "       "

    if imgui.TreeNode(text) then
        for i = 1, #obj.friend_object_ptrs do
            local friend_ptr = obj.friend_object_ptrs[i]
            local subtitle = string.format("friend%d", i)

            if null_ptr(friend_ptr) then
                imgui.Text(string.format("%s%s: null", fake_indent, subtitle))
            elseif friend_ptr == obj_ptr then
                imgui.Text(string.format("%s%s: self", fake_indent, subtitle))
            else
                local is_dupe = false
                local dupe_of = -1
                for j = 1, i - 1 do
                    local other_friend_ptr = obj.friend_object_ptrs[j]
                    if other_friend_ptr == friend_ptr then
                        is_dupe = true
                        dupe_of = j
                        break
                    end
                end

                if is_dupe then
                    imgui.Text(string.format("%s%s: friend%d", fake_indent, subtitle, dupe_of))
                else
                    visualize_object_hierarchy(subtitle, friend_ptr, visited, depth + 1)
                end
            end
        end

        imgui.TreePop()
    end
end

local function examine_object_graph(obj_ptr, visited, depth)
    if depth > lowest_depth then
        lowest_depth = depth
    end

    if depth > max_depth then
        too_deep = true
        return
    end

    for i = 1, #visited do
        if visited[i] == obj_ptr then
            has_circular_refs = true
            return
        end
    end

    table.insert(visited, obj_ptr)

    local obj = parse_pso_base_object(obj_ptr)

    for i = 1, #obj.friend_object_ptrs do
        local friend_ptr = obj.friend_object_ptrs[i]
        if not null_ptr(friend_ptr) then
            if friend_ptr == obj_ptr then
                has_self_refs = true
            end
            examine_object_graph(friend_ptr, visited, depth + 1)
        end
    end
end

local num_visited = 0

local function present()
    imgui.PushStyleVar("IndentSpacing", 10)

    local current_obj_ptr = root_obj_ptr

    if imgui.Begin("object-hierarchy-visualizer", nil, {}) then
        local text = string.format("%d uniq, depth %d", num_visited, lowest_depth)

        if too_deep then
            text = text .. ", too deep"
        end

        if has_self_refs then
            text = text .. ", has loops"
        else
            text = text .. ", no loops"
        end

        if has_circular_refs then
            text = text .. ", cyclic"
        else
            text = text .. ", tree"
        end

        imgui.Text(text)

        visualize_object_hierarchy("root", current_obj_ptr, {}, 0)
    end

    imgui.PopStyleVar()
end

local function init()
    local visited = {}
    examine_object_graph(root_obj_ptr, visited, 0)
    num_visited = #visited

    return {
        name = "object-hierarchy-visualizer",
        present = present
    }
end

return {
    __addon = {
        init = init
    }
}
