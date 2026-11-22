"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-09', 'filename': 'IPTV.swift', 'station': 'GorSources', 'required_types': ['IPTVChannel', 'IPTVCountry', 'IPTVContinent', 'IPTVScreen', 'ClickableTextRow', 'IPTVPanel'], 'required_tokens': ['IPTVChannel', 'IPTVCountry', 'IPTVContinent', 'IPTVScreen', 'iconFor', 'randomIPTVIcon', 'countryName', 'playbackCountryCode', 'channelInCountry', 'playbackTitle', 'ClickableTextRow', 'IPTVPanel'], 'required_extensions': [('MusicBtn', 'setAlpha', (('_', ('CGFloat',)),)), ('MusicBtn', 'updateLabel', (('_', ('String',)),))]}

if __name__ == '__main__':
    main(CONFIG)
