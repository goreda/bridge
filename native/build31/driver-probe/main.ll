; ModuleID = '/Users/builder/clone/out/driver-probe/temp/TemporaryDirectory.CdCKHx/main-1.o'
source_filename = "/Users/builder/clone/out/driver-probe/temp/TemporaryDirectory.CdCKHx/main-1.o"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx13.0.0"

%swift.full_existential_type = type { ptr, %swift.type }
%swift.type = type { i64 }
%Any = type { [24 x i8], ptr }
%TSi = type <{ i64 }>
%TSa = type <{ %Ts12_ArrayBufferV }>
%Ts12_ArrayBufferV = type <{ %Ts14_BridgeStorageV }>
%Ts14_BridgeStorageV = type <{ ptr }>
%swift.metadata_response = type { ptr, i64 }

@"$sypN" = external global %swift.full_existential_type
@"$sSiN" = external global %swift.type, align 8
@"\01l_entry_point" = private constant { i32, i32 } { i32 trunc (i64 sub (i64 ptrtoint (ptr @main to i64), i64 ptrtoint (ptr @"\01l_entry_point" to i64)) to i32), i32 0 }, section "__TEXT, __swift5_entry, regular, no_dead_strip", align 4
@".str.1.\0A" = private unnamed_addr constant [2 x i8] c"\0A\00"
@".str.1. " = private unnamed_addr constant [2 x i8] c" \00"
@__swift_reflection_version = linkonce_odr hidden constant i16 3
@llvm.swift_module_hash = private constant [16 x i8] zeroinitializer, section "__LLVM,__swift_modhash"
@llvm.used = appending global [4 x ptr] [ptr @main, ptr @"\01l_entry_point", ptr @__swift_reflection_version, ptr @llvm.swift_module_hash], section "llvm.metadata"

define i32 @main(i32 %0, ptr %1) #0 {
  %3 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %4 = extractvalue { ptr, ptr } %3, 0
  %5 = extractvalue { ptr, ptr } %3, 1
  %6 = getelementptr inbounds i8, ptr %4, i64 32
  %7 = call swiftcc i64 @"$s5probe0A5ValueSiyF"()
  %8 = getelementptr inbounds nuw %Any, ptr %6, i32 0, i32 1
  store ptr @"$sSiN", ptr %8, align 8
  %9 = getelementptr inbounds nuw %Any, ptr %6, i32 0, i32 0
  %10 = getelementptr inbounds nuw %Any, ptr %6, i32 0, i32 0
  %11 = getelementptr inbounds nuw %TSi, ptr %10, i32 0, i32 0
  store i64 %7, ptr %11, align 8
  %12 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %4, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %13 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %14 = extractvalue { i64, ptr } %13, 0
  %15 = extractvalue { i64, ptr } %13, 1
  %16 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %17 = extractvalue { i64, ptr } %16, 0
  %18 = extractvalue { i64, ptr } %16, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %12, i64 %14, ptr %15, i64 %17, ptr %18)
  call void @swift_bridgeObjectRelease(ptr %18) #1
  call void @swift_bridgeObjectRelease(ptr %15) #1
  call void @swift_bridgeObjectRelease(ptr %12) #1
  ret i32 0
}

declare swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64, ptr) #0

declare swiftcc i64 @"$s5probe0A5ValueSiyF"() #0

define linkonce_odr hidden swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %0, ptr %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca %TSa, align 8
  store ptr %1, ptr %3, align 8
  call void @llvm.lifetime.start.p0(i64 8, ptr %4)
  %5 = getelementptr inbounds nuw %TSa, ptr %4, i32 0, i32 0
  %6 = getelementptr inbounds nuw %Ts12_ArrayBufferV, ptr %5, i32 0, i32 0
  %7 = getelementptr inbounds nuw %Ts14_BridgeStorageV, ptr %6, i32 0, i32 0
  store ptr %0, ptr %7, align 8
  %8 = call swiftcc %swift.metadata_response @"$sSaMa"(i64 0, ptr %1) #3
  %9 = extractvalue %swift.metadata_response %8, 0
  call swiftcc void @"$sSa12_endMutationyyF"(ptr %9, ptr swiftself captures(none) dereferenceable(8) %4)
  %10 = getelementptr inbounds nuw %TSa, ptr %4, i32 0, i32 0
  %11 = getelementptr inbounds nuw %Ts12_ArrayBufferV, ptr %10, i32 0, i32 0
  %12 = getelementptr inbounds nuw %Ts14_BridgeStorageV, ptr %11, i32 0, i32 0
  %13 = load ptr, ptr %12, align 8
  call void @llvm.lifetime.end.p0(i64 8, ptr %4)
  ret ptr %13
}

define linkonce_odr hidden swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"() #0 {
  %1 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.1. ", i64 1, i1 true)
  %2 = extractvalue { i64, ptr } %1, 0
  %3 = extractvalue { i64, ptr } %1, 1
  %4 = insertvalue { i64, ptr } undef, i64 %2, 0
  %5 = insertvalue { i64, ptr } %4, ptr %3, 1
  ret { i64, ptr } %5
}

define linkonce_odr hidden swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"() #0 {
  %1 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.1.\0A", i64 1, i1 true)
  %2 = extractvalue { i64, ptr } %1, 0
  %3 = extractvalue { i64, ptr } %1, 1
  %4 = insertvalue { i64, ptr } undef, i64 %2, 0
  %5 = insertvalue { i64, ptr } %4, ptr %3, 1
  ret { i64, ptr } %5
}

declare swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr, i64, ptr, i64, ptr) #0

; Function Attrs: nounwind
declare void @swift_bridgeObjectRelease(ptr) #1

declare swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr, i64, i1) #0

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr captures(none)) #2

define linkonce_odr hidden swiftcc void @"$sSa12_endMutationyyF"(ptr %0, ptr swiftself captures(none) dereferenceable(8) %1) #0 {
  %3 = getelementptr inbounds nuw %TSa, ptr %1, i32 0, i32 0
  %4 = getelementptr inbounds nuw %Ts12_ArrayBufferV, ptr %3, i32 0, i32 0
  %5 = getelementptr inbounds nuw %Ts14_BridgeStorageV, ptr %4, i32 0, i32 0
  %6 = load ptr, ptr %5, align 8
  %7 = getelementptr inbounds nuw %TSa, ptr %1, i32 0, i32 0
  %8 = getelementptr inbounds nuw %Ts12_ArrayBufferV, ptr %7, i32 0, i32 0
  %9 = getelementptr inbounds nuw %Ts14_BridgeStorageV, ptr %8, i32 0, i32 0
  store ptr %6, ptr %9, align 8
  ret void
}

declare swiftcc %swift.metadata_response @"$sSaMa"(i64, ptr) #0

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr captures(none)) #2

attributes #0 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #1 = { nounwind }
attributes #2 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #3 = { nounwind memory(none) }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7, !8, !9, !10, !11}
!swift.module.flags = !{!12}
!llvm.linker.options = !{!13, !14, !15, !16, !17, !18}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 26, i32 5]}
!1 = !{i32 1, !"Objective-C Version", i32 2}
!2 = !{i32 1, !"Objective-C Image Info Version", i32 0}
!3 = !{i32 1, !"Objective-C Image Info Section", !"__DATA,__objc_imageinfo,regular,no_dead_strip"}
!4 = !{i32 4, !"Objective-C Garbage Collection", i32 100861696}
!5 = !{i32 1, !"Objective-C Class Properties", i32 64}
!6 = !{i32 1, !"Objective-C Enforce ClassRO Pointer Signing", i8 0}
!7 = !{i32 1, !"wchar_size", i32 4}
!8 = !{i32 8, !"PIC Level", i32 2}
!9 = !{i32 7, !"uwtable", i32 1}
!10 = !{i32 7, !"frame-pointer", i32 1}
!11 = !{i32 1, !"Swift Version", i32 7}
!12 = !{!"standard-library", i1 false}
!13 = !{!"-lswiftSwiftOnoneSupport"}
!14 = !{!"-lswiftCore"}
!15 = !{!"-lswift_Concurrency"}
!16 = !{!"-lswift_StringProcessing"}
!17 = !{!"-lobjc"}
!18 = !{!"-lswiftCompatibilityPacks"}
