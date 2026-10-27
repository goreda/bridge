        setWipeCurtain(true);
        window.setTimeout(() => resetDevice({ preserveLegacy: false }), 1800);
    };
    /* A newer service copy never replaces this page's changes: they are merged first. Unsent edits (a dictated
       paragraph, typing in progress) are read from the page itself, so they survive another device's save. */
    /* sync-quota-recovery r1 (Contracts A/B): unconfirmed IndexedDB recovery records are the source of
       truth for their pieces until a push confirms them - they overlay both the reload restore and the
       merge result, so another device's copy never renders over unconfirmed local text. */
    const overlayRecovery = async (state) => {
        let recs; try { recs = await recoveryRecords(); } catch { return state; }
        if (!state || !Array.isArray(state.pieces) || !recs.length) return state;
        const pieces = [...state.pieces];
        for (const r of recs) {
            const i = pieces.findIndex(p => p && p.id === r.pieceId);
            if (i >= 0) {
                const p = pieces[i], ci = p.current || 0, versions = [...(p.versions || [])];
                if (versions[ci]) versions[ci] = { ...versions[ci], lines: r.lines };
                pieces[i] = { ...p, title: r.title, versions };
            } // else: the piece is gone from the state - the record stays HELD (panel copy/download), never auto-restored
        }
        return { ...state, pieces };
    };
    /* r2 (architect notice inventory A): the rail's status feed, copy/download handlers and mount moved
       INTO the normal sync panel (account.js SyncControl); no floating box exists any more. */
    const applyRemote = async (r, adminRetry = false) => {
        if (!currentRead(r)) return;
        if (r.restoring && r.state === null) {
            adminProfilesBinding.current=token()||null;adminProfilesRemote.current=undefined;adminProfilesHeld.current=false;adminProfiles.current={};
            acceptRemote(r.rev, r.state, r); // confirmed empty server state, not a failed read
            return;
        }
        const capturedAdminEpoch = adminEditEpoch.current;
        const retryAdminRestore = () => {
            if (!currentRead(r)) return;
            if (!adminRetry) return applyRemote(r, true); // one fresh merge only, never an unbounded retry loop
            showNote('admin layout changed during sync · latest edit kept for the next sync');
        };
        const captured = saveStateRef.current(); // keep fresh page edits even when storage is full
        let scopeNow = cachedScope(token()); // refreshed below; the write-back reuses it
        let local = captured ?? null;
        if (!local) {
            // the stored copy is applied only under its own profile's scope: another
            // account's residue (e.g. after a wipe) is never merged into this account
            try {
                scopeNow = await scopeForToken(token());
                const read = readScopedState(storeGet(STATE_KEY), scopeNow);
                local = read.apply ? JSON.parse(read.stateText) : null;
            } catch { local = null; }
        }
        // First restore is additive: a missing local piece is not proof of deletion.
        // Stale or legacy bases cannot erase the current remote shelf.
        const base = r.restoring ? null : (getBase() ?? (syncLoading.current ? local : null));
        if (!currentRead(r)) return;
        if (adminEditEpoch.current !== capturedAdminEpoch) return retryAdminRestore();
        if (adminRetry && local && typeof local === 'object' && !Array.isArray(local) && adminProfilesBinding.current === token() && adminProfilesRemote.current !== undefined && !adminProfilesHeld.current) {
            local = { ...local, adminProfiles: adminProfilesRemote.current }; // current edit even when restore blocks ordinary save
        }
        const merged = mergeStates(base, local, r.state);
        const custScope = isJoined() ? scopeNow : null;
        let keptAside = false;
        if (merged.adminConflicts.some(conflict => conflict.reason?.endsWith('-corrupt-held'))) {
            // key-level hold: pieces, settings and the revision keep merging. Each unreadable raw value keeps its own custody:
            // remote stays unchanged on the account, local and sync-base copies are kept aside in the scoped device copy.
            const rawAdmin = merged.state.adminProfiles;
            adminProfilesHeld.current = rawAdmin != null && !cleanAdminProfileState(rawAdmin);
            if (adminProfilesHeld.current) { adminProfilesRemote.current = rawAdmin; adminProfilesBinding.current = token() || null; }
            for (const conflict of merged.adminConflicts) {
                const h = conflict.held;
                if (!h || typeof h !== 'object') continue;
                if (h.local != null && !cleanAdminProfileState(h.local) && holdAdminRaw('local', h.local, custScope)) keptAside = true;
                if (h.base != null && !cleanAdminProfileState(h.base) && holdAdminRaw('base', h.base, custScope)) keptAside = true;
            }
            if (adminProfilesHeld.current) showNote('admin layout data on the account is unreadable · left unchanged there, edits paused' + (keptAside ? ' · unreadable copies on this device are kept aside' : ''));
            else if (keptAside) showNote('unreadable admin layout data on this device was kept aside · the account copy is used');
        }
        return overlayRecovery(merged.state).then(overlaid => { // Contract A: unconfirmed records stay rendered
        if (!currentRead(r)) return;
        if (adminEditEpoch.current !== capturedAdminEpoch) return retryAdminRestore();
        const text = JSON.stringify(overlaid);
        const same = local && JSON.stringify(local) === text;
        let persisted = true;
        try { persisted = writeScopedWithCustody(custScope, overlaid).durable; } catch { persisted = false; }
        if (persisted) adminCustodyDirty.current = false;
        else if (adminCustodyDirty.current) {
            // unreadable admin data was set aside in memory only: never advance the revision or replace the sync base
            // (which would delete the only other copy) until the scoped device copy really holds it
            showNote('could not keep unreadable admin layout data aside (device storage) · this sync is paused until it can');
            return;
        }
        if (!same) {
            // this device's scroll wins, restored once the new pieces have laid out
            const sc = scrollerRef.current;
            const keep = sc ? sc.scrollTop : 0;
            applySaved(text, true);
            if (sc)
                requestAnimationFrame(() =>
                    requestAnimationFrame(() => sc.scrollTo({ top: keep })),
                );
        }
        acceptRemote(r.rev, r.state, r);
        if (merged.conflicts.length) {
            const ids = merged.conflicts.map((c) => c.piece);
            const saved = saveRecovery({ kind: 'merge', conflicts: merged.conflicts, local: piecesOf(local, ids), remote: piecesOf(r.state, ids) });
            showNote('a piece conflict was found' + (saved ? ' · a recovery copy of the differing pieces is on this device' : ' · recovery copy unavailable'));
        }
        if (!r.restoring && merged.localChanged && local) {
            const editEpoch = localEditEpoch.current;
            void pushMerged(overlaid, r.rev).then(res => // the pushed merge carries the overlaid records
                handleMergeReceipt(res, overlaid, { current: result => currentWrite(result) && localEditEpoch.current === editEpoch, retry: retryMerged }));
        }
        });
