# Citation Verification — T7 Input/EventBridge Audit (2026-05-27)

| Agent | Finding | File | Cited Lines | Status | Notes |
|---|---|---|---|---|---|
| T7-A | F1 | input_manager.cpp | 186-192 | **VERIFIED** | SetPortRouter / SetControllerPortDeviceCallback match verbatim |
| T7-A | F2 | input_manager.cpp | 229-277 | **VERIFIED** | OnInputState body matches; GetButton/GetAnalog/GetPointer calls confirmed |
| T7-A | F3 | input_manager.cpp | 310-316 | **VERIFIED** | OnSensorGetInput matches verbatim |
| T7-A | F4 | event_bridge.cpp | 75-105 | **VERIFIED** | Initialize with napi_tsfn_release matches; abort not present |
| T7-A | F5 | event_bridge.cpp | 217-221 | **VERIFIED** | napi_call_function return ignored; delete follows immediately |
| T7-A | F6 | input_port_router.cpp | 27-32 | **VERIFIED** | ClearPortStateLocked matches verbatim |
| T7-A | F7 | input_port_router.cpp | 180-197 | **VERIFIED** | ResolvePortForDevice auto-bind logic confirmed |
| T7-A | F8 | input_snapshot.h | 196, 203 | **VERIFIED** | atomic<int16_t> line 196, atomic<float> line 203 confirmed |
| T7-B | F1 | engine_napi_common.h | 133-136 | **VERIFIED** | size >= outSize path only logs, no napi_throw_* |
| T7-B | F2 | engine_input_napi.cpp | 138-160 | **CITATION_DRIFT** | Actual code 138-158; logic identical, off by 2 lines |
| T7-B | F3 | engine_input_napi.cpp | 232 | **VERIFIED** | napi_define_properties return value discarded |
| T7-B | F4 | engine_input_napi.cpp | 57-68 | **VERIFIED** | double→int cast at line 68 confirmed |
| T7-B | F5 | engine_input_napi.cpp | 92 | **VERIFIED** | char idBuf[256] at line 92 confirmed |
| T7-C | F1 | RuntimeInputCommandBridge.ets | 36-37 | **VERIFIED** | X-axis call result not captured, Y returned |
| T7-C | F2 | LibretroEventHub.ets | 256-277 | **VERIFIED** | getInstance() singleton, no destroy/reset method |
| T7-C | F3 | InputLayoutPage.ets | 351-363 | **VERIFIED** | showSavedToast uses setTimeout |
| T7-C | F4 | RuntimeInputPortController.ets | 27-38, 41 | **VERIFIED** | NAPI calls without engine-ready guard confirmed |
| T7-C | F5 | MultiplayerInputPage.ets | 100-102 | **VERIFIED** | aboutToAppear() directly calls refreshDevices() (sync NAPI) |
| T7-C | F6 | InputPortRouting.ts | 80-91 | **VERIFIED** | findPortAssignment returns sentinel object silently |
| T7-C | F7 | RuntimeInputCommandBridge.ets | 26-38 | **VERIFIED** | sendRuntimeAnalog hardcodes id=0 and id=1 |
| T7-C | F8 | LibretroEventHub.ets | 301-312 | **VERIFIED** | replayLatest catch block calls removeListener |

**Summary: 20 VERIFIED / 1 CITATION_DRIFT / 0 FILE_MISSING / 0 FORMAT_ERROR** (21 total)

T7-B F2 drift: agent cited lines 138-160, actual code ends at 158. Content identical; finding stands.
