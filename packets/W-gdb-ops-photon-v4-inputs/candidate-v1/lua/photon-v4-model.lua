-- Pure decision model. No mpv globals or scene factor hidden in the shader.
local M = { version = 4 }
local function finite(x) return type(x)=='number' and x==x and x>-math.huge and x<math.huge end
local function positive(x, name) assert(finite(x) and x>0, name); return x end
local function nonnegative(x, name) assert(finite(x) and x>=0, name); return x end
function M.cell(source_height, output_height, source_cell, confidence, look_fraction, trim)
    positive(source_height,'source height'); positive(output_height,'output height')
    positive(look_fraction,'look fraction'); positive(trim,'trim')
    nonnegative(confidence,'confidence'); assert(confidence<=1,'confidence')
    local v = look_fraction*output_height
    if source_cell~=nil and confidence>=0.6 then v=positive(source_cell,'source cell')*output_height/source_height end
    local result=math.max(0.6,v*trim); assert(finite(result),"cell overflow"); return result
end
function M.pwl(y, xs, ys)
    assert(finite(y) and #xs==#ys and #xs>=2,'curve')
    for i=1,#xs do
        assert(finite(xs[i]),'knot'); nonnegative(ys[i],'sigma')
        if i>1 then assert(xs[i]>xs[i-1],'ordered knots') end
    end
    if y<=xs[1] then return ys[1] end
    for i=2,#xs do if y<=xs[i] then
        local t=(y-xs[i-1])/(xs[i]-xs[i-1]); return ys[i-1]+t*(ys[i]-ys[i-1])
    end end
    return ys[#ys]
end
function M.sigma(target, source, floor, compression, amount, strength, enabled)
    positive(target,'target'); nonnegative(source,'source'); positive(floor,'floor'); assert(floor<=1,'floor')
    positive(compression,'compression'); assert(compression>=1,'compression')
    nonnegative(amount,'amount'); nonnegative(strength,'strength')
    if not enabled or amount==0 or strength==0 then return 0 end
    local t=target*compression
    local result=math.sqrt(math.max(t*t-source*source,floor*floor*t*t))*amount*strength
    assert(finite(result),"sigma overflow"); return result
end
return M
