-- Protocol core. Integration must bind Receiver calls to actual control handlers.
-- Receipts assert host parameter acceptance, never GPU or physical user identity.
local M = {VERSION = 1}
-- Source ranges/count and selected admission floor, not newly calibrated adaptive values.
-- learning_samples/look_min/look_max are preserved source values, not calibration.
M.LIMITS = {mult_floor=.5, mult_ceiling=8, manual_min=0, manual_max=30,
    look_min=0, look_max=100, learning_samples=3}
local function finite(v) return type(v) == 'number' and v == v and math.abs(v) < math.huge end
local function integer(v) return finite(v) and v >= 0 and v % 1 == 0 end
local function copy(t) local out = {}; for k,v in pairs(t) do out[k]=v end; return out end
local function doc_equal(a,b) return a and b and a.gen == b.gen and a.name == b.name end
local function valid_doc(d) return type(d)=='table' and integer(d.gen) and type(d.name)=='string' and d.name~='' end
M.finite = finite

-- Bounded, in-memory diagnostics. No frame bytes, names, URLs or blocking IO.
function M.ring(capacity)
    assert(integer(capacity) and capacity > 0, 'explicit positive ring capacity required')
    local r = {capacity=capacity, count=0, head=0, dropped=0, data={}}
    function r:record(event)
        self.head=self.head % self.capacity+1
        if self.count==self.capacity then self.dropped=self.dropped+1 else self.count=self.count+1 end
        self.data[self.head]=copy(event)
    end
    function r:snapshot()
        local out={}; for i=1,self.count do
            local index=(self.head-self.count+i-1)%self.capacity+1
            out[#out+1]=copy(self.data[index])
        end
        return out,self.dropped
    end
    return r
end

function M.receiver(config)
    assert(finite(config.base) and config.base>0)
    assert(integer(config.cache_capacity) and config.cache_capacity>0)
    assert(type(config.apply)=='function' and type(config.clock)=='function')
    local r={base=config.base, revision=0, serial=0, action_seq=0, command_high=0,
        cache={}, order={}, enabled=false, suppressed=false, accepted_strength=config.base}
    local function log(kind, fields)
        if config.trace then local e=copy(fields or {});e.kind=kind;e.clock='receiver';e.t=config.clock();config.trace(e) end
    end
    function r:bind(doc, enabled)
        assert(valid_doc(doc))
        -- Same identity cannot reset high-water fences or revision.
        if self.doc and doc_equal(doc,self.doc) then return false end
        self.doc=copy(doc);self.revision=0;self.serial=0;self.action_seq=0;self.command_high=0
        self.cache={};self.order={};self.manual=nil;self.suppressed=false;self.enabled=enabled==true
        log('RESET',{doc_gen=doc.gen});return true
    end
    function r:invalidate(reason, enabled)
        self.revision=self.revision+1;self.manual=nil;self.suppressed=false
        if enabled~=nil then self.enabled=enabled==true end
        -- High-water and cached receipts survive same-document invalidation.
        log('RESET',{doc_gen=self.doc and self.doc.gen,revision=self.revision,reason=reason})
    end
    function r:publish() self.serial=self.serial+1;return self.serial end
    local function receipt(self,c,status,reason,origin)
        return {version=2,doc_gen=self.doc and self.doc.gen,doc_name=self.doc and self.doc.name,
            command_id=c.id,revision=self.revision,serial=self.serial,status=status,reason=reason,
            origin=origin,accepted_strength=self.accepted_strength,base=self.base}
    end
    local function signature(c)
        return table.concat({c.doc.gen,c.doc.name,c.id,c.revision,c.serial_floor,
            string.format('%.17g',c.mult),string.format('%.17g',c.expected_strength)},'\0')
    end
    local function emit(v) log('ACK_SEND',{command_id=v.command_id,revision=v.revision,status=v.status,reason=v.reason});return copy(v) end
    function r:auto(c)
        log('RECEIVE',{command_id=type(c)=='table' and c.id or nil})
        if type(c)~='table' or c.version~=2 or not valid_doc(c.doc) or not integer(c.id) or c.id<1
            or not integer(c.revision) or not integer(c.serial_floor) or not finite(c.mult)
            or c.mult<M.LIMITS.mult_floor or c.mult>M.LIMITS.mult_ceiling or not finite(c.expected_strength) then
            return emit(receipt(self,type(c)=='table' and c or {},'REJECTED','malformed'))
        end
        if not doc_equal(c.doc,self.doc) then return emit(receipt(self,c,'REJECTED','document')) end
        local sig=signature(c);local old=self.cache[c.id]
        if old then
            if old.signature~=sig then return emit(receipt(self,c,'REJECTED','duplicate-conflict')) end
            return emit(old.receipt)
        end
        if c.id<=self.command_high then return emit(receipt(self,c,'REJECTED','stale-evicted')) end
        self.command_high=c.id
        local reason
        if c.revision~=self.revision then reason='revision'
        elseif c.serial_floor>self.serial then reason='serial'
        elseif not self.enabled then reason='disabled'
        elseif self.suppressed then reason='manual-override'
        elseif c.expected_strength~=self.base*c.mult then reason='base-mismatch'
        elseif c.expected_strength<M.LIMITS.manual_min or c.expected_strength>M.LIMITS.manual_max then reason='host-range' end
        local v
        if reason then v=receipt(self,c,'REJECTED',reason)
        else
            local accepted=self.base*c.mult
            if accepted==self.accepted_strength then v=receipt(self,c,'NOOP',nil,'AUTO_COMMAND')
            else
                -- Adapter must apply the exact value without clamping and return true only after host acceptance.
                local ok,result=pcall(config.apply,accepted)
                if not ok or result~=true then v=receipt(self,c,'REJECTED','apply-failed')
                else self.accepted_strength=accepted;self.revision=self.revision+1
                    v=receipt(self,c,'APPLIED',nil,'AUTO_COMMAND') end
            end
        end
        self.cache[c.id]={signature=sig,receipt=copy(v)};self.order[#self.order+1]=c.id
        if #self.order>config.cache_capacity then local id=table.remove(self.order,1);self.cache[id]=nil end
        log(v.status,{command_id=c.id,revision=self.revision,accepted_strength=self.accepted_strength})
        return emit(v)
    end
    function r:manual_strength(value)
        -- Only actual validated manual handler may invoke this method.
        if not self.doc or not self.enabled or not finite(value) then return nil,'invalid-manual' end
        value=math.max(M.LIMITS.manual_min,math.min(M.LIMITS.manual_max,value)) -- Existing manual range, not adaptive tuning.
        local ok,result=pcall(config.apply,value)
        if not ok or result~=true then return nil,'apply-failed' end
        self.accepted_strength=value;self.revision=self.revision+1;self.action_seq=self.action_seq+1
        self.suppressed=true
        self.manual={doc=copy(self.doc),action_id=self.action_seq,revision=self.revision,
            strength=value,kind='strength',origin='MANUAL_STRENGTH'}
        log('MANUAL_ACCEPT',{action_id=self.action_seq,revision=self.revision,accepted_strength=value})
        return copy(self.manual)
    end
    function r:resume(doc,action_id,revision)
        if not self.enabled or not self.manual or not doc_equal(doc,self.doc)
            or action_id~=self.manual.action_id or revision~=self.revision then return false,'stale-resume' end
        if self.manual.resumed then return true,'duplicate' end
        self.suppressed=false;self.manual.resumed=true;log('RESUME',{action_id=action_id,revision=revision});return true
    end
    return r
end

function M.sender(config)
    assert(type(config.clock)=='function')
    local s={state='UNBOUND',seq=0,serial=0,revision=0}
    local function log(kind,fields)
        if config.trace then local e=copy(fields or {});e.kind=kind;e.clock='sender';e.t=config.clock();config.trace(e) end
    end
    function s:bind(doc,revision,serial,base)
        if not valid_doc(doc) or not integer(revision) or not integer(serial) or not finite(base) or base<=0 then return false end
        if self.doc and doc_equal(self.doc,doc) then return false end
        self.doc=copy(doc);self.revision=revision;self.serial=serial;self.base=base;self.seq=0
        self.pending=nil;self.learner=nil;self.acknowledged=nil;self.state='READY';return true
    end
    function s:hold(reason)
        self.state='HOLD_UNRESOLVED';self.pending=nil;self.learner=nil;self.reason=reason
        self.receiver_suppression_unresolved=true
        log('HOLD',{reason=reason,doc_gen=self.doc and self.doc.gen})
    end
    function s:send(mult)
        if self.state~='READY' or not finite(mult) or mult<M.LIMITS.mult_floor or mult>M.LIMITS.mult_ceiling then return nil end
        local expected_strength=self.base*mult
        if expected_strength<M.LIMITS.manual_min or expected_strength>M.LIMITS.manual_max then
            log('SEND_SKIPPED',{reason='host-range',mult=mult,expected_strength=expected_strength})
            return nil,'host-range'
        end
        self.seq=self.seq+1
        local c={version=2,doc=copy(self.doc),id=self.seq,revision=self.revision,
            serial_floor=self.serial,mult=mult,expected_strength=expected_strength}
        self.pending={command=c,sent_at=config.clock()};self.state='AUTO_PENDING'
        log('SEND',{command_id=c.id,revision=c.revision,mult=mult});return copy(c)
    end
    function s:ack(a)
        local p=self.pending
        if not p then log('ACK_IGNORED',{});return false end
        local c=p.command
        if type(a)=='table' and a.version==2 and a.command_id==c.id
            and a.doc_gen==self.doc.gen and a.doc_name==self.doc.name
            and a.status=='REJECTED' then
            -- Rejection is not application. Keep explicit HOLD until separately
            -- source-bound reconciliation; never retry over a new manual action.
            self.rejected=copy(a);self:hold('rejected:'..tostring(a.reason));return false
        end
        if type(a)~='table' or a.version~=2 or a.command_id~=c.id or a.doc_gen~=self.doc.gen
            or a.doc_name~=self.doc.name or not integer(a.revision) or not integer(a.serial)
            or a.serial<c.serial_floor or a.origin~='AUTO_COMMAND' or a.base~=self.base
            or a.accepted_strength~=c.expected_strength
            or not ((a.status=='APPLIED' and a.revision==c.revision+1) or (a.status=='NOOP' and a.revision==c.revision)) then
            self:hold('invalid-ack');return false
        end
        self.acknowledged=copy(a);self.revision=a.revision;self.serial=a.serial
        self.pending=nil;self.state='READY';self.reason=nil
        log('ACK_RECEIVE',{command_id=c.id,revision=a.revision,latency=config.clock()-p.sent_at});return true
    end
    function s:timeout()
        -- No invented production T. Unqualified timeout remains pending/HOLD.
        if not self.pending then return end
        if not finite(config.timeout) or config.timeout<=0 then
            log('STALL',{command_id=self.pending.command.id,age=config.clock()-self.pending.sent_at,unqualified=true});return
        end
        if config.clock()-self.pending.sent_at>=config.timeout then self:hold('timeout') end
    end
    function s:diagnostics()
        return {state=self.state,reason=self.reason,
            receiver_suppression_unresolved=self.receiver_suppression_unresolved==true,
            rejected_reason=self.rejected and self.rejected.reason}
    end
    -- No automatic reconcile API: a new source-bound lifecycle/controller
    -- decision must establish READY. Repeated same-document bind cannot bypass HOLD.
    function s:manual(a)
        -- Caller must pass a source-bound receiver receipt, not numeric disagreement.
        if config.manual_identity_bound~=true then self:hold('manual-identity-unbound');return false end
        if type(a)~='table' or not doc_equal(a.doc,self.doc) or a.origin~='MANUAL_STRENGTH' or a.kind~='strength'
            or not integer(a.action_id) or a.action_id<1 or not integer(a.revision)
            or a.revision<=self.revision or not finite(a.strength) then self:hold('invalid-manual');return false end
        self.pending=nil;self.revision=a.revision;self.state='MANUAL'
        self.learner={action=copy(a),values={},scene=nil};return true
    end
    function s:sample(value,scene,revision_after)
        local l=self.learner
        if self.state~='MANUAL' or not l or not finite(value) or value<=M.LIMITS.look_min or value>=M.LIMITS.look_max
            or scene==nil or revision_after~=l.action.revision then self:hold('learning-fence');return false end
        if l.scene~=nil and scene~=l.scene then self:hold('scene-change');return false end
        l.scene=scene;l.values[#l.values+1]=value
        if #l.values<M.LIMITS.learning_samples then return false end -- Preserved existing count.
        table.sort(l.values);local learned=l.values[2]
        if not config.save or config.save(learned,l.action)~=true then self:hold('save-failed');return false end
        if not config.resume or config.resume(self.doc,l.action.action_id,l.action.revision)~=true then self:hold('resume-failed');return false end
        self.look_R=learned;self.learner=nil;self.state='READY';self.reason=nil;self.receiver_suppression_unresolved=false;log('LOOK_LEARNED',{action_id=l.action.action_id});return true
    end
    return s
end

-- New namespace only. IO adapter must atomically persist and report failures.
M.namespace='~~state/gor_look_manual_v2.txt'
M.schema='manual-action-v2'
function M.decode_look(text)
    if type(text)~='string' then return nil end
    local value=text:match('^manual%-action%-v2\n([^\n]+)\n$')
    value=tonumber(value)
    if not finite(value) or value<=M.LIMITS.look_min or value>=M.LIMITS.look_max then return nil end
    return value
end
function M.encode_look(value)
    if not finite(value) or value<=M.LIMITS.look_min or value>=M.LIMITS.look_max then return nil end
    return M.schema..'\n'..string.format('%.17g',value)..'\n'
end
return M
