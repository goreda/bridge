-- U-G2 explicit manual-event learner. No renderer, timer or automatic resume.
local M={}
local bounds={strength={.01,10},amount={.01,64},size={.01,64}}
local function finite(v)return type(v)=='number'and v==v and v>-math.huge and v<math.huge end
local function validkey(s)return type(s)=='string'and #s>0 and #s<=120 and s:match('^[%w_.:|%-]+$')end
local function median(t)local a={};for i,v in ipairs(t)do a[i]=v end;table.sort(a);local n=#a;return n%2==1 and a[(n+1)/2]or(a[n/2]+a[n/2+1])/2 end
M.median=median
function M.new(utils,path,warning)
 local self={state={version=2,classes={}},path=path,warning=warning or function()end,readOnly=false}
 local function valid(s)
  if type(s)~='table'or s.version~=2 or type(s.classes)~='table'then return false end
  if s.legacy~=nil and(not finite(s.legacy)or s.legacy<.16-1e-9 or s.legacy>1.5625+1e-9)then return false end
  for k in pairs(s)do if k~='version'and k~='classes'and k~='legacy'then return false end end
  local count=0
  for class,parameters in pairs(s.classes)do
   count=count+1;if count>64 or not validkey(class)or type(parameters)~='table'then return false end
   for parameter,events in pairs(parameters)do
    if not bounds[parameter]or type(events)~='table'or #events>64 then return false end
    local n=0;for k in pairs(events)do if type(k)~='number'or k%1~=0 or k<1 or k>#events then return false end;n=n+1 end;if n~=#events then return false end
    local ids={}
    for _,e in ipairs(events)do
     if type(e)~='table'or not validkey(e.id)or ids[e.id]or(e.mode~='on'and e.mode~='off')or not finite(e.value)or e.value<bounds[parameter][1]or e.value>bounds[parameter][2]then return false end
     for k in pairs(e)do if k~='id'and k~='mode'and k~='value'then return false end end
     ids[e.id]=true
    end
   end
  end
  return true
 end
 function self:load()
  if type(self.path)~='string'or not(self.path:match('^/')or self.path:match('^%a:[/\\]'))then self.readOnly=true;return false end
  local f=io.open(self.path,'rb');if not f then return true end;local bytes=f:read(262145);f:close()
  if #bytes>262144 then self.readOnly=true;self.warning('look file too large; untouched');return false end
  local scalar=tonumber(bytes)
  if scalar and finite(scalar)and scalar>=.16-1e-9 and scalar<=1.5625+1e-9 then self.state.legacy=scalar;self.scalarBytes=bytes;return true end
  local ok,s=pcall(utils.parse_json,bytes)
  if ok and valid(s)then self.state=s;return true end
  self.readOnly=true;self.warning('invalid look file; untouched');return false
 end
 function self:save()
  if self.readOnly or not valid(self.state)then return false end
  if self.scalarBytes then
   local old=io.open(self.path..'.pre-ug2','rb')
   if old then old:close()else local b=io.open(self.path..'.pre-ug2','wb');if not b then return false end;local ok=b:write(self.scalarBytes);local closed=b:close();if not ok or not closed then return false end end
  end
  local bytes=utils.format_json(self.state);if type(bytes)~='string'or #bytes>262144 then return false end
  local f=io.open(self.path..'.tmp','wb');if not f then return false end;local ok=f:write(bytes);local flushed=f:flush();local closed=f:close();if not ok or not flushed or not closed then return false end
  return not not os.rename(self.path..'.tmp',self.path)
 end
 function self:record(class,parameter,id,value,mode)
  if self.readOnly or not validkey(class)or not validkey(id)or not bounds[parameter]or not finite(value)or value<bounds[parameter][1]or value>bounds[parameter][2]or(mode~='on'and mode~='off')then return false end
  local previous=utils.format_json(self.state);local c=self.state.classes[class]
  if not c then local n=0;for _ in pairs(self.state.classes)do n=n+1 end;if n>=64 then return false end;c={};self.state.classes[class]=c end
  local events=c[parameter]or{};for _,e in ipairs(events)do if e.id==id then return false end end;if #events>=64 then return false end
  events[#events+1]={id=id,value=value,mode=mode};c[parameter]=events
  if not self:save()then self.state=utils.parse_json(previous);self.warning('look save failed; previous preference retained');return false end
  return true
 end
 function self:target(class,parameter)
  local c=self.state.classes[class];local e=c and c[parameter];if not e or #e<3 then return nil,e and #e or 0 end
  local values={};for i=math.max(1,#e-8),#e do values[#values+1]=e[i].value end;return median(values),#e
 end
 function self:solve(class,parameter,automatic)
  if not finite(automatic)or automatic<0 then return nil end
  if automatic==0 then return 0 end
  local target=self:target(class,parameter);if not target then return automatic end
  return .5*automatic+.5*target
 end
 function self:reset()
  if type(self.path)~='string'or not(self.path:match('^/')or self.path:match('^%a:[/\\]'))then return false end
  -- Explicit reset can clear an invalid file too, but never touches the backup.
  local ok,err,code=os.remove(self.path);if not ok and code~=2 then return false end
  local f=io.open(self.path,'rb');if f then f:close();return false end
  self.state={version=2,classes={}};self.readOnly=false;self.scalarBytes=nil;return true
 end
 self:load();return self
end
return M
