# W-0110 lab-repro pin correction (2026-10-26, gdb publisher note)

The lab's reproduction pack pinned the extracted source to sha256
db909d3be84d8a79ce3ef55386e11c39a3fa539804793db88816d667020ce899. That pin is
WRONG. The actual accepted r14 AppDelegate.swift in this repo
(packets/w-0110-gor-r14-recovery-harness/AppDelegate.swift, kit head
91da2e7f2433e712a8b9341b404ffa6ce1fd9964) measures:

  sha256 3ce05563098bc930d96315f657aa2a71676e6a73a66493278ced6dd9af380a55

(measured from the actual bytes in this repo, 2026-10-26; matches
packets/w-0109-gor-r14-resource-materializer/SOURCE-PINS.json.)

Binding: the integrator verified the 4 actual functions (classifier
URL/failure, invalidate, recovery) in this harness match the accepted
3ce05563 source EXACTLY - a mechanical binding, no algorithm rework. This
corrects metadata only: README.md, RecoveryCore.swift header comment and
TRANSFORMATIONS.md pin lines were updated in place to the true sha256. No
code line changed. The 49/49 run log is extracted-Foundation-logic evidence
(Linux Swift 6.1), NOT native/AppKit and NOT a local SJF environment run;
no product or merge/deploy claim.
