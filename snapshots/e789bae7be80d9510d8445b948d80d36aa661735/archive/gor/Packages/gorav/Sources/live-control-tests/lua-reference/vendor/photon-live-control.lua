-- Live-only actuator. No VOD helpers modified. All qualification values supplied.
local M={VERSION=1}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
function M.new(config)
    local s={gamma=config.initial_gamma,state='UNKNOWN',velocity=0}
    assert(finite(s.gamma))
    local function qualified()
        return config.qualified==true and finite(config.rate) and config.rate>0
            and finite(config.stale_age) and config.stale_age>0
            and finite(config.callback_gap) and config.callback_gap>0
            and finite(config.reference_interval) and config.reference_interval>0
            and finite(config.retention) and config.retention>0 and config.retention<1
            and type(config.classify_cut)=='function' and type(config.settled)=='function'
            and type(config.target)=='function' and type(config.velocity)=='function'
            and finite(config.max_settlement_samples) and config.max_settlement_samples>=1
            and config.max_settlement_samples%1==0
    end
    function s:hold(reason)
        self.state=self.cut_pending and 'CUT_HOLD_UNKNOWN' or 'UNKNOWN'
        self.target=nil;self.velocity=0;self.previous=nil;self.reason=reason
        if self.cut_pending then self.cut_profiles={} end
    end
    function s:diagnostics()
        return {state=self.state,reason=self.reason,cut_pending=self.cut_pending==true,
            settlement_samples=self.cut_profiles and #self.cut_profiles or 0,held_gamma=self.gamma}
    end
    function s:observe(profile)
        if type(profile)~='table' or profile.doc==nil or profile.id==nil or not finite(profile.t)
            or not finite(profile.pts) or not finite(profile.pbs) then self:hold('invalid-profile');return false end
        if self.doc~=profile.doc then
            self:hold('document');self.doc=profile.doc;self.last_id=nil;self.last_pts=nil;self.last_t=nil;self.cut_profiles=nil;self.cut_pending=false;self.state='UNKNOWN'
        end
        if self.last_id and (profile.id<=self.last_id or profile.pts<=self.last_pts or profile.t<=self.last_t) then
            self:hold('repeated-profile');return false
        end
        local old=self.previous
        self.last_id=profile.id;self.last_pts=profile.pts;self.last_t=profile.t
        -- Feed fresh observations even while gamma is held.
        if config.feed then config.feed(profile) end
        if not qualified() then self:hold('unqualified');return false end
        if old and profile.t-old.t>config.stale_age then self:hold('observation-gap');old=nil end
        local cut=old and config.classify_cut(old,profile) or nil
        if cut=='candidate' or cut=='confirmed' then
            self.state='CUT_HOLD';self.cut_pending=true;self.velocity=0;self.target=nil;self.cut_profiles={profile}
        elseif self.cut_pending then
            self.cut_profiles=self.cut_profiles or {}
            if #self.cut_profiles>=config.max_settlement_samples then
                -- Bounded sliding settlement window; pending cut survives every hold.
                table.remove(self.cut_profiles,1)
            end
            self.cut_profiles[#self.cut_profiles+1]=profile
            if config.settled(self.cut_profiles)==true then
                self.state='READY';self.reason=nil;self.cut_profiles=nil;self.cut_pending=false
            else self.state='CUT_HOLD';self.reason='settlement-unresolved' end
        else self.state='READY';self.reason=nil end
        if self.state=='READY' then
            if old then self.velocity=config.velocity(old,profile,self.velocity) else self.velocity=0 end
            local target=config.target(profile,self.velocity)
            if not finite(target) then self:hold('invalid-target');return false end
            self.target=target
        end
        self.previous=profile;return self.state=='READY'
    end
    function s:tick(now)
        if not finite(now) then self:hold('invalid-clock');return nil end
        local last=self.last_tick;self.last_tick=now
        if not qualified() then self:hold('unqualified');return nil end
        if not last then return nil end
        local dt=now-last
        if dt<=0 or dt>config.callback_gap then self:hold('callback-gap');return nil end
        if not self.last_t or now<self.last_t or now-self.last_t>config.stale_age then self:hold('stale');return nil end
        if self.state~='READY' or not finite(self.target) then return nil end
        local distance=self.target-self.gamma
        local proposal=distance*(1-config.retention^(dt/config.reference_interval))
        local step=math.max(-config.rate*dt,math.min(config.rate*dt,proposal))
        if math.abs(step)>math.abs(distance) then step=distance end
        local candidate=self.gamma+step
        if not finite(candidate) then self:hold('invalid-actuator');return nil end
        -- Full precision internal state. Caller rounds output separately and dedupes setter.
        self.gamma=candidate;return candidate
    end
    return s
end
return M
