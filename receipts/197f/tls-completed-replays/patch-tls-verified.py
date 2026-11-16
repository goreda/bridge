#!/usr/bin/env python3
# Add mandatory certificate+hostname verification, configurable trust roots,
# never a verify=false option. Layer on clean pin with close-order repair.
import pathlib,sys,re
root=pathlib.Path(sys.argv[1]);p=root/'Sources/CFFmpeg/shim.h';s=p.read_text()
start=s.index('static inline int gorav_r3_open_input(');end=s.index('\n/* =================== AUTHORED_R10',start)
s=s[:start]+'''static inline int gorav_r3_open_input_verified(AVFormatContext **ctx, const char *url,
                                      const char *headers, const char *cookies,
                                      const char *ca_file) {
    AVDictionary *d = NULL;
    int rc = av_dict_set(&d, "tls_verify", "1", 0);
    if (rc < 0) goto cleanup;
    if (ca_file && ca_file[0]) {
        rc = av_dict_set(&d, "ca_file", ca_file, 0);
        if (rc < 0) goto cleanup;
    }
    if (headers && headers[0]) {
        rc = av_dict_set(&d, "headers", headers, 0);
        if (rc < 0) goto cleanup;
    }
    if (cookies && cookies[0]) {
        rc = av_dict_set(&d, "cookies", cookies, 0);
        if (rc < 0) goto cleanup;
    }
    rc = avformat_open_input(ctx, url, NULL, &d);
cleanup:
    av_dict_free(&d);
    return rc;
}
/* Existing C callers also use authenticated transport with system trust. */
static inline int gorav_r3_open_input(AVFormatContext **ctx, const char *url,
                                      const char *headers, const char *cookies) {
    return gorav_r3_open_input_verified(ctx, url, headers, cookies, NULL);
}
''' + s[end:];p.write_text(s)
p=root/'Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift';s=p.read_text()
s=s.replace('    public var openDeadlineSeconds: Double?', '''    /// Optional absolute PEM trust-root path, owned by caller. nil uses system
    /// trust. Verification and hostname matching are always enabled.
    public var tlsCAFile: String?
    public var openDeadlineSeconds: Double?''',1)
s=s.replace('openDeadlineSeconds: Double? = nil) {','openDeadlineSeconds: Double? = nil, tlsCAFile: String? = nil) {',1)
s=s.replace('        self.openDeadlineSeconds = openDeadlineSeconds','        self.tlsCAFile = tlsCAFile\n        self.openDeadlineSeconds = openDeadlineSeconds',1)
s=s.replace('        if let deadline = openDeadlineSeconds {','''        if let path = tlsCAFile {
            guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SourceOpenOptionsError.tlsTrustInvalid
            }
        }
        if let deadline = openDeadlineSeconds {''',1)
s=s.replace('    case deadlineInvalid','    case deadlineInvalid\n    case tlsTrustInvalid',1)
s=s.replace('                gorav_r3_open_input(ctx, urlC, hC, cC)','''                withOpt(options.tlsCAFile) { caC in
                    gorav_r3_open_input_verified(ctx, urlC, hC, cC, caC)
                }''',1)
p.write_text(s)
