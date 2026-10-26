//! Primary OpenType1.9.1 OS2 assigned spans, custody in docs/engine/sources.
use crate::os2_consistency::UnicodeRangeSpan;
pub const ASSIGNED_SPANS:&[UnicodeRangeSpan]=&[
    UnicodeRangeSpan{first:0x0000,last:0x007F,bit:0}, // Basic Latin
    UnicodeRangeSpan{first:0x0080,last:0x00FF,bit:1}, // Latin-1 Supplement
    UnicodeRangeSpan{first:0x0100,last:0x017F,bit:2}, // Latin Extended-A
    UnicodeRangeSpan{first:0x0180,last:0x024F,bit:3}, // Latin Extended-B
    UnicodeRangeSpan{first:0x0250,last:0x02AF,bit:4}, // IPA Extensions
    UnicodeRangeSpan{first:0x1D00,last:0x1D7F,bit:4}, // Phonetic Extensions
    UnicodeRangeSpan{first:0x1D80,last:0x1DBF,bit:4}, // Phonetic Extensions Supplement
    UnicodeRangeSpan{first:0x02B0,last:0x02FF,bit:5}, // Spacing Modifier Letters
    UnicodeRangeSpan{first:0xA700,last:0xA71F,bit:5}, // Modifier Tone Letters
    UnicodeRangeSpan{first:0x0300,last:0x036F,bit:6}, // Combining Diacritical Marks
    UnicodeRangeSpan{first:0x1DC0,last:0x1DFF,bit:6}, // Combining Diacritical Marks Supplement
    UnicodeRangeSpan{first:0x0370,last:0x03FF,bit:7}, // Greek and Coptic
    UnicodeRangeSpan{first:0x2C80,last:0x2CFF,bit:8}, // Coptic
    UnicodeRangeSpan{first:0x0400,last:0x04FF,bit:9}, // Cyrillic
    UnicodeRangeSpan{first:0x0500,last:0x052F,bit:9}, // Cyrillic Supplement
    UnicodeRangeSpan{first:0x2DE0,last:0x2DFF,bit:9}, // Cyrillic Extended-A
    UnicodeRangeSpan{first:0xA640,last:0xA69F,bit:9}, // Cyrillic Extended-B
    UnicodeRangeSpan{first:0x0530,last:0x058F,bit:10}, // Armenian
    UnicodeRangeSpan{first:0x0590,last:0x05FF,bit:11}, // Hebrew
    UnicodeRangeSpan{first:0xA500,last:0xA63F,bit:12}, // Vai
    UnicodeRangeSpan{first:0x0600,last:0x06FF,bit:13}, // Arabic
    UnicodeRangeSpan{first:0x0750,last:0x077F,bit:13}, // Arabic Supplement
    UnicodeRangeSpan{first:0x07C0,last:0x07FF,bit:14}, // NKo
    UnicodeRangeSpan{first:0x0900,last:0x097F,bit:15}, // Devanagari
    UnicodeRangeSpan{first:0x0980,last:0x09FF,bit:16}, // Bangla
    UnicodeRangeSpan{first:0x0A00,last:0x0A7F,bit:17}, // Gurmukhi
    UnicodeRangeSpan{first:0x0A80,last:0x0AFF,bit:18}, // Gujarati
    UnicodeRangeSpan{first:0x0B00,last:0x0B7F,bit:19}, // Odia
    UnicodeRangeSpan{first:0x0B80,last:0x0BFF,bit:20}, // Tamil
    UnicodeRangeSpan{first:0x0C00,last:0x0C7F,bit:21}, // Telugu
    UnicodeRangeSpan{first:0x0C80,last:0x0CFF,bit:22}, // Kannada
    UnicodeRangeSpan{first:0x0D00,last:0x0D7F,bit:23}, // Malayalam
    UnicodeRangeSpan{first:0x0E00,last:0x0E7F,bit:24}, // Thai
    UnicodeRangeSpan{first:0x0E80,last:0x0EFF,bit:25}, // Lao
    UnicodeRangeSpan{first:0x10A0,last:0x10FF,bit:26}, // Georgian
    UnicodeRangeSpan{first:0x2D00,last:0x2D2F,bit:26}, // Georgian Supplement
    UnicodeRangeSpan{first:0x1B00,last:0x1B7F,bit:27}, // Balinese
    UnicodeRangeSpan{first:0x1100,last:0x11FF,bit:28}, // Hangul Jamo
    UnicodeRangeSpan{first:0x1E00,last:0x1EFF,bit:29}, // Latin Extended Additional
    UnicodeRangeSpan{first:0x2C60,last:0x2C7F,bit:29}, // Latin Extended-C
    UnicodeRangeSpan{first:0xA720,last:0xA7FF,bit:29}, // Latin Extended-D
    UnicodeRangeSpan{first:0x1F00,last:0x1FFF,bit:30}, // Greek Extended
    UnicodeRangeSpan{first:0x2000,last:0x206F,bit:31}, // General Punctuation
    UnicodeRangeSpan{first:0x2E00,last:0x2E7F,bit:31}, // Supplemental Punctuation
    UnicodeRangeSpan{first:0x2070,last:0x209F,bit:32}, // Superscripts And Subscripts
    UnicodeRangeSpan{first:0x20A0,last:0x20CF,bit:33}, // Currency Symbols
    UnicodeRangeSpan{first:0x20D0,last:0x20FF,bit:34}, // Combining Diacritical Marks For Symbols
    UnicodeRangeSpan{first:0x2100,last:0x214F,bit:35}, // Letterlike Symbols
    UnicodeRangeSpan{first:0x2150,last:0x218F,bit:36}, // Number Forms
    UnicodeRangeSpan{first:0x2190,last:0x21FF,bit:37}, // Arrows
    UnicodeRangeSpan{first:0x27F0,last:0x27FF,bit:37}, // Supplemental Arrows-A
    UnicodeRangeSpan{first:0x2900,last:0x297F,bit:37}, // Supplemental Arrows-B
    UnicodeRangeSpan{first:0x2B00,last:0x2BFF,bit:37}, // Miscellaneous Symbols and Arrows
    UnicodeRangeSpan{first:0x2200,last:0x22FF,bit:38}, // Mathematical Operators
    UnicodeRangeSpan{first:0x2A00,last:0x2AFF,bit:38}, // Supplemental Mathematical Operators
    UnicodeRangeSpan{first:0x27C0,last:0x27EF,bit:38}, // Miscellaneous Mathematical Symbols-A
    UnicodeRangeSpan{first:0x2980,last:0x29FF,bit:38}, // Miscellaneous Mathematical Symbols-B
    UnicodeRangeSpan{first:0x2300,last:0x23FF,bit:39}, // Miscellaneous Technical
    UnicodeRangeSpan{first:0x2400,last:0x243F,bit:40}, // Control Pictures
    UnicodeRangeSpan{first:0x2440,last:0x245F,bit:41}, // Optical Character Recognition
    UnicodeRangeSpan{first:0x2460,last:0x24FF,bit:42}, // Enclosed Alphanumerics
    UnicodeRangeSpan{first:0x2500,last:0x257F,bit:43}, // Box Drawing
    UnicodeRangeSpan{first:0x2580,last:0x259F,bit:44}, // Block Elements
    UnicodeRangeSpan{first:0x25A0,last:0x25FF,bit:45}, // Geometric Shapes
    UnicodeRangeSpan{first:0x2600,last:0x26FF,bit:46}, // Miscellaneous Symbols
    UnicodeRangeSpan{first:0x2700,last:0x27BF,bit:47}, // Dingbats
    UnicodeRangeSpan{first:0x3000,last:0x303F,bit:48}, // CJK Symbols And Punctuation
    UnicodeRangeSpan{first:0x3040,last:0x309F,bit:49}, // Hiragana
    UnicodeRangeSpan{first:0x30A0,last:0x30FF,bit:50}, // Katakana
    UnicodeRangeSpan{first:0x31F0,last:0x31FF,bit:50}, // Katakana Phonetic Extensions
    UnicodeRangeSpan{first:0x3100,last:0x312F,bit:51}, // Bopomofo
    UnicodeRangeSpan{first:0x31A0,last:0x31BF,bit:51}, // Bopomofo Extended
    UnicodeRangeSpan{first:0x3130,last:0x318F,bit:52}, // Hangul Compatibility Jamo
    UnicodeRangeSpan{first:0xA840,last:0xA87F,bit:53}, // Phags-pa
    UnicodeRangeSpan{first:0x3200,last:0x32FF,bit:54}, // Enclosed CJK Letters And Months
    UnicodeRangeSpan{first:0x3300,last:0x33FF,bit:55}, // CJK Compatibility
    UnicodeRangeSpan{first:0xAC00,last:0xD7AF,bit:56}, // Hangul Syllables
    UnicodeRangeSpan{first:0x10000,last:0x10FFFF,bit:57}, // Non-Plane 0
    UnicodeRangeSpan{first:0x10900,last:0x1091F,bit:58}, // Phoenician
    UnicodeRangeSpan{first:0x4E00,last:0x9FFF,bit:59}, // CJK Unified Ideographs
    UnicodeRangeSpan{first:0x2E80,last:0x2EFF,bit:59}, // CJK Radicals Supplement
    UnicodeRangeSpan{first:0x2F00,last:0x2FDF,bit:59}, // Kangxi Radicals
    UnicodeRangeSpan{first:0x2FF0,last:0x2FFF,bit:59}, // Ideographic Description Characters
    UnicodeRangeSpan{first:0x3400,last:0x4DBF,bit:59}, // CJK Unified Ideographs Extension A
    UnicodeRangeSpan{first:0x20000,last:0x2A6DF,bit:59}, // CJK Unified Ideographs Extension B
    UnicodeRangeSpan{first:0x3190,last:0x319F,bit:59}, // Kanbun
    UnicodeRangeSpan{first:0xE000,last:0xF8FF,bit:60}, // Private Use Area (plane 0)
    UnicodeRangeSpan{first:0x31C0,last:0x31EF,bit:61}, // CJK Strokes
    UnicodeRangeSpan{first:0xF900,last:0xFAFF,bit:61}, // CJK Compatibility Ideographs
    UnicodeRangeSpan{first:0x2F800,last:0x2FA1F,bit:61}, // CJK Compatibility Ideographs Supplement
    UnicodeRangeSpan{first:0xFB00,last:0xFB4F,bit:62}, // Alphabetic Presentation Forms
    UnicodeRangeSpan{first:0xFB50,last:0xFDFF,bit:63}, // Arabic Presentation Forms-A
    UnicodeRangeSpan{first:0xFE20,last:0xFE2F,bit:64}, // Combining Half Marks
    UnicodeRangeSpan{first:0xFE10,last:0xFE1F,bit:65}, // Vertical Forms
    UnicodeRangeSpan{first:0xFE30,last:0xFE4F,bit:65}, // CJK Compatibility Forms
    UnicodeRangeSpan{first:0xFE50,last:0xFE6F,bit:66}, // Small Form Variants
    UnicodeRangeSpan{first:0xFE70,last:0xFEFF,bit:67}, // Arabic Presentation Forms-B
    UnicodeRangeSpan{first:0xFF00,last:0xFFEF,bit:68}, // Halfwidth And Fullwidth Forms
    UnicodeRangeSpan{first:0xFFF0,last:0xFFFF,bit:69}, // Specials
    UnicodeRangeSpan{first:0x0F00,last:0x0FFF,bit:70}, // Tibetan
    UnicodeRangeSpan{first:0x0700,last:0x074F,bit:71}, // Syriac
    UnicodeRangeSpan{first:0x0780,last:0x07BF,bit:72}, // Thaana
    UnicodeRangeSpan{first:0x0D80,last:0x0DFF,bit:73}, // Sinhala
    UnicodeRangeSpan{first:0x1000,last:0x109F,bit:74}, // Myanmar
    UnicodeRangeSpan{first:0x1200,last:0x137F,bit:75}, // Ethiopic
    UnicodeRangeSpan{first:0x1380,last:0x139F,bit:75}, // Ethiopic Supplement
    UnicodeRangeSpan{first:0x2D80,last:0x2DDF,bit:75}, // Ethiopic Extended
    UnicodeRangeSpan{first:0x13A0,last:0x13FF,bit:76}, // Cherokee
    UnicodeRangeSpan{first:0x1400,last:0x167F,bit:77}, // Unified Canadian Aboriginal Syllabics
    UnicodeRangeSpan{first:0x1680,last:0x169F,bit:78}, // Ogham
    UnicodeRangeSpan{first:0x16A0,last:0x16FF,bit:79}, // Runic
    UnicodeRangeSpan{first:0x1780,last:0x17FF,bit:80}, // Khmer
    UnicodeRangeSpan{first:0x19E0,last:0x19FF,bit:80}, // Khmer Symbols
    UnicodeRangeSpan{first:0x1800,last:0x18AF,bit:81}, // Mongolian
    UnicodeRangeSpan{first:0x2800,last:0x28FF,bit:82}, // Braille Patterns
    UnicodeRangeSpan{first:0xA000,last:0xA48F,bit:83}, // Yi Syllables
    UnicodeRangeSpan{first:0xA490,last:0xA4CF,bit:83}, // Yi Radicals
    UnicodeRangeSpan{first:0x1700,last:0x171F,bit:84}, // Tagalog
    UnicodeRangeSpan{first:0x1720,last:0x173F,bit:84}, // Hanunoo
    UnicodeRangeSpan{first:0x1740,last:0x175F,bit:84}, // Buhid
    UnicodeRangeSpan{first:0x1760,last:0x177F,bit:84}, // Tagbanwa
    UnicodeRangeSpan{first:0x10300,last:0x1032F,bit:85}, // Old Italic
    UnicodeRangeSpan{first:0x10330,last:0x1034F,bit:86}, // Gothic
    UnicodeRangeSpan{first:0x10400,last:0x1044F,bit:87}, // Deseret
    UnicodeRangeSpan{first:0x1D000,last:0x1D0FF,bit:88}, // Byzantine Musical Symbols
    UnicodeRangeSpan{first:0x1D100,last:0x1D1FF,bit:88}, // Musical Symbols
    UnicodeRangeSpan{first:0x1D200,last:0x1D24F,bit:88}, // Ancient Greek Musical Notation
    UnicodeRangeSpan{first:0x1D400,last:0x1D7FF,bit:89}, // Mathematical Alphanumeric Symbols
    UnicodeRangeSpan{first:0xF0000,last:0xFFFFD,bit:90}, // Private Use (plane 15)
    UnicodeRangeSpan{first:0x100000,last:0x10FFFD,bit:90}, // Private Use (plane 16)
    UnicodeRangeSpan{first:0xFE00,last:0xFE0F,bit:91}, // Variation Selectors
    UnicodeRangeSpan{first:0xE0100,last:0xE01EF,bit:91}, // Variation Selectors Supplement
    UnicodeRangeSpan{first:0xE0000,last:0xE007F,bit:92}, // Tags
    UnicodeRangeSpan{first:0x1900,last:0x194F,bit:93}, // Limbu
    UnicodeRangeSpan{first:0x1950,last:0x197F,bit:94}, // Tai Le
    UnicodeRangeSpan{first:0x1980,last:0x19DF,bit:95}, // New Tai Lue
    UnicodeRangeSpan{first:0x1A00,last:0x1A1F,bit:96}, // Buginese
    UnicodeRangeSpan{first:0x2C00,last:0x2C5F,bit:97}, // Glagolitic
    UnicodeRangeSpan{first:0x2D30,last:0x2D7F,bit:98}, // Tifinagh
    UnicodeRangeSpan{first:0x4DC0,last:0x4DFF,bit:99}, // Yijing Hexagram Symbols
    UnicodeRangeSpan{first:0xA800,last:0xA82F,bit:100}, // Syloti Nagri
    UnicodeRangeSpan{first:0x10000,last:0x1007F,bit:101}, // Linear B Syllabary
    UnicodeRangeSpan{first:0x10080,last:0x100FF,bit:101}, // Linear B Ideograms
    UnicodeRangeSpan{first:0x10100,last:0x1013F,bit:101}, // Aegean Numbers
    UnicodeRangeSpan{first:0x10140,last:0x1018F,bit:102}, // Ancient Greek Numbers
    UnicodeRangeSpan{first:0x10380,last:0x1039F,bit:103}, // Ugaritic
    UnicodeRangeSpan{first:0x103A0,last:0x103DF,bit:104}, // Old Persian
    UnicodeRangeSpan{first:0x10450,last:0x1047F,bit:105}, // Shavian
    UnicodeRangeSpan{first:0x10480,last:0x104AF,bit:106}, // Osmanya
    UnicodeRangeSpan{first:0x10800,last:0x1083F,bit:107}, // Cypriot Syllabary
    UnicodeRangeSpan{first:0x10A00,last:0x10A5F,bit:108}, // Kharoshthi
    UnicodeRangeSpan{first:0x1D300,last:0x1D35F,bit:109}, // Tai Xuan Jing Symbols
    UnicodeRangeSpan{first:0x12000,last:0x123FF,bit:110}, // Cuneiform
    UnicodeRangeSpan{first:0x12400,last:0x1247F,bit:110}, // Cuneiform Numbers and Punctuation
    UnicodeRangeSpan{first:0x1D360,last:0x1D37F,bit:111}, // Counting Rod Numerals
    UnicodeRangeSpan{first:0x1B80,last:0x1BBF,bit:112}, // Sundanese
    UnicodeRangeSpan{first:0x1C00,last:0x1C4F,bit:113}, // Lepcha
    UnicodeRangeSpan{first:0x1C50,last:0x1C7F,bit:114}, // Ol Chiki
    UnicodeRangeSpan{first:0xA880,last:0xA8DF,bit:115}, // Saurashtra
    UnicodeRangeSpan{first:0xA900,last:0xA92F,bit:116}, // Kayah Li
    UnicodeRangeSpan{first:0xA930,last:0xA95F,bit:117}, // Rejang
    UnicodeRangeSpan{first:0xAA00,last:0xAA5F,bit:118}, // Cham
    UnicodeRangeSpan{first:0x10190,last:0x101CF,bit:119}, // Ancient Symbols
    UnicodeRangeSpan{first:0x101D0,last:0x101FF,bit:120}, // Phaistos Disc
    UnicodeRangeSpan{first:0x102A0,last:0x102DF,bit:121}, // Carian
    UnicodeRangeSpan{first:0x10280,last:0x1029F,bit:121}, // Lycian
    UnicodeRangeSpan{first:0x10920,last:0x1093F,bit:121}, // Lydian
    UnicodeRangeSpan{first:0x1F030,last:0x1F09F,bit:122}, // Domino Tiles
    UnicodeRangeSpan{first:0x1F000,last:0x1F02F,bit:122}, // Mahjong Tiles
];
