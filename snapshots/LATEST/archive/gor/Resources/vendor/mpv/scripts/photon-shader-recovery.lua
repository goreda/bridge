-- Baseline-only renderer recovery. Never treats list presence as compile proof.
local M={}
function M.new(mp,utils,opts)
 local self={latched=false,busy=false,failures=0,started=false,prefix=opts.prefix,ready=false}
 local fallback=opts.directory..opts.prefix..'-safe.glsl'
 local safe_prefix=opts.prefix..'-safe'
 local function write(path,bytes)
  local f,e=io.open(path,'wb');if not f then return false,e end
  local ok,err=f:write(bytes);if ok then ok,err=f:flush()end;local closed,cerr=f:close();return ok and closed,err or cerr
 end
 local function contains(list,path)for _,p in ipairs(list or {})do if p==path then return true end end;return false end
 local state_path=mp.command_native({'expand-path','~~state/'..opts.prefix..'-recovery.json'})
 local state_valid=type(state_path)=='string'and(state_path:match('^/')or state_path:match('^%a:[/\\]'))
 if state_valid then local dir=state_path:match('^(.*)[/\\][^/\\]+$');pcall(mp.command_native,{name='subprocess',args={'mkdir','-p',dir},playback_only=false,capture_stderr=true})end
 local function persist(record)
  if not state_valid then return false,'unresolved state path'end
  local ok,e=write(state_path..'.tmp',utils.format_json(record));if not ok then return false,e end
  return os.rename(state_path..'.tmp',state_path)
 end
 local function source_hash()
  local f=io.open(fallback,'rb');if not f then return 'unavailable'end;local bytes=f:read('*a');f:close()
  return bytes==opts.source and opts.sourceSHA256 or 'MISMATCH'
 end
 local function async_failure_hash(path,record)
  if not path then return end
  local function run(args,next_args)
   mp.command_native_async({name='subprocess',args=args,playback_only=false,capture_stdout=true,capture_stderr=true},function(ok,r)
    local h=ok and r and r.status==0 and (r.stdout or ''):match('^([a-fA-F0-9]+)')or nil
    -- A delayed hash belongs to its captured failure, never a later state.
    -- Do not let callback completion order roll back durable/HUD user-data state.
    if self.record~=record then return end
    if h and #h==64 then record.failedSHA256=h:lower();record.hashStatus='measured';persist(record);mp.set_property_native('user-data/'..opts.prefix..'-recovery',record)
    elseif next_args then run(next_args,nil)else record.hashStatus='unavailable';persist(record)end
   end)
  end
  run({'shasum','-a','256',path},{'sha256sum',path})
 end
 function self:recover(reason)
  if self.busy or not opts.enabled()then return false end
  self.busy=true;local failed=opts.active()
  self.failures=self.failures+1
  -- One canonical, independently named path forces reparse after a corrupt path.
  -- If that known fallback itself fails, retain its entry and expose hard failure.
  if self.latched and reason=='renderer parse/compile failure' then
   self.hardFailure=true
  else
   local ok,err=write(fallback,opts.source)
   if not ok then self.hardFailure=true;self.writeError=tostring(err)
   else
    self.latched=true;self.prefix=safe_prefix;self.recoveringUntil=mp.get_time()+.5
    opts.activate(fallback)
    local list=mp.get_property_native('glsl-shaders')or {}
    for _,p in ipairs(list)do if opts.owns(p)and p~=fallback then mp.commandv('change-list','glsl-shaders','remove',p)end end
    -- Atomic option operations avoid overwriting a sibling's simultaneous restore.
    mp.commandv('change-list','glsl-shaders','remove',fallback)
    mp.commandv('change-list','glsl-shaders',opts.kind=='grain'and 'pre'or 'append',fallback)
    self.ready=contains(mp.get_property_native('glsl-shaders'),fallback)
    if not self.ready then self.hardFailure=true end
   end
  end
  local failed_hash=failed and 'pending'or 'missing'
  local observed_hash=source_hash()
  if observed_hash~=opts.sourceSHA256 then self.hardFailure=true end
  local record={version=1,kind=opts.kind,time=os.date('!%Y-%m-%dT%H:%M:%SZ'),reason=reason,failedPath=failed,failedSHA256=failed_hash,fallbackPath=fallback,fallbackSHA256=opts.sourceSHA256,fallbackObservedSHA256=observed_hash,fallbackListed=self.ready,hardFailure=self.hardFailure or false,writeError=self.writeError,failures=self.failures,compileStatus='not attested by list presence'}
  local saved,err=persist(record);record.stateSaved=not not saved;record.stateError=err
  self.record=record
  local line='Photon '..opts.kind..': '..(self.hardFailure and 'SHADER FAILURE - recovery needs attention'or 'spatial fallback active')..(saved and ''or ' (state save failed)')
  mp.set_property_native('user-data/'..opts.prefix..'-recovery',record)
  mp.msg.warn(line) -- Diagnostic log only; photon HUD owns visible recovery status.
  self.busy=false
  async_failure_hash(failed,record)
  if opts.parameters then opts.parameters()end
  return not self.hardFailure
 end
 function self:verify()
  if not opts.enabled()then return end
  if self.busy or self.suspended or not self.started then return end
  local path=opts.active();if not path or not contains(mp.get_property_native('glsl-shaders'),path)then self:recover('missing shader entry')end
 end
 local original_set=mp.set_property_native
 mp.set_property_native=function(name,value,...)
  local result=original_set(name,value,...)
  if name=='glsl-shaders'and not self.busy then self.started=true;self:verify()end
  return result
 end
 if mp.register_idle then mp.register_idle(function()self:verify()end)end
 mp.observe_property('glsl-shaders','native',function()self:verify()end)
 mp.add_periodic_timer(.25,function()self:verify()end)
 mp.enable_messages('warn')
 mp.register_event('log-message',function(e)
  if not opts.enabled()or self.busy or (e.level~='warn'and e.level~='error'and e.level~='fatal')then return end
  local prefix=e.prefix or '';if not prefix:match('^vo/')then return end
  local text=e.text or ''
  if text:find('Failed to parse user shader',1,true)or text:find('shader compilation failed',1,true)or text:find('Failed to compile',1,true)or text:find('shader compile log (status=0)',1,true)or text:find('Failed compiling/linking',1,true)or text:find('Failed executing hook',1,true)then
   -- mpv does not always include the failing path. Restore each enabled Photon
   -- stage conservatively; retain the unassociated renderer attribution.
   if not self.latched then self:recover('renderer parse/compile failure')
   elseif not self.hardFailure and (text:find(fallback,1,true)or source_hash()=='MISMATCH')then self:recover('renderer parse/compile failure')end
  end
 end)
 return self
end
return M
