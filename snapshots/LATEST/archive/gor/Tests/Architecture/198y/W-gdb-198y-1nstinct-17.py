"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-17', 'filename': 'PPControllerMenuQueries.swift', 'station': 'GorUI', 'required_types': ['CropInvariant'], 'required_tokens': ['queryMenuPayload', 'surfaceDrawableReceipt', 'setSubtitlePositionPreset', 'nativeAudioDeviceSnapshot', 'CropInvariant', 'mayChange', 'keptLine', 'transitionLine', 'fits', 'logPipCrop'], 'required_extensions': [('PPController', 'queryMenuPayload', (('_', ('String',)),)), ('PPController', 'surfaceDrawableReceipt', ()), ('PPController', 'setSubtitlePositionPreset', (('_', ('Int',)),)), ('PPController', 'nativeAudioDeviceSnapshot', ()), ('PPController', 'logPipCrop', (('_', ('String',)), ('frame', ('NSRect',))))]}

if __name__ == '__main__':
    main(CONFIG)
