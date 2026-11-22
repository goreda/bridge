import os, sys, subprocess, gc
import numpy as np
import torch
NUNIF = os.path.expanduser("~/s4/190t/nunif")
sys.path.insert(0, NUNIF); os.chdir(NUNIF)

CLIP = os.path.expanduser("~/s4/clips/tos_test_320x180_48f.mp4")
FRAME = os.path.expanduser("~/s4/clips/tos_test_frame.png")
OUT = "/tmp/x2"
W, H, N = 320, 180, 48

def load_frames():
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", CLIP, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    a = np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3)
    return torch.from_numpy(a.copy()).permute(0, 3, 1, 2).float() / 255.0

def load_frame():
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", FRAME, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    a = np.frombuffer(raw, np.uint8).reshape(1, H, W, 3)
    return torch.from_numpy(a.copy()).permute(0, 3, 1, 2).float() / 255.0

def save_sbs(left, right, name):
    # left,right: [B,3,H,W] -> side-by-side mp4/png
    sbs = torch.cat([left, right], dim=3)
    arr = (sbs.permute(0, 2, 3, 1).clamp(0, 1) * 255).byte().numpy()
    raw = arr.tobytes()
    b, h, w = arr.shape[0], arr.shape[1], arr.shape[2]
    if b == 1:
        subprocess.run(["ffmpeg", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
                        "-i", "-", f"{OUT}/{name}.png", "-y"], input=raw, check=True)
    else:
        subprocess.run(["ffmpeg", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
                        "-framerate", "24", "-i", "-", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
                        f"{OUT}/{name}.mp4", "-y"], input=raw, check=True)

def get_depth(frames):
    from iw3.depth_models.video_depth_anything_model import VideoDepthAnythingModel
    dm = VideoDepthAnythingModel("VDA_S").load(gpu=-1, resolution=266)
    depths = []
    with torch.inference_mode():
        for i in range(frames.shape[0]):
            ret = dm.infer(frames[i:i+1], streaming=True, enable_amp=False)
            if ret is not None:
                depths.append(ret)
        ret = dm.flush(enable_amp=False)
        if ret is not None:
            depths.append(ret)
    depth = torch.cat(depths, dim=0)
    assert depth.shape[0] == frames.shape[0], (depth.shape, frames.shape)
    del dm; gc.collect()
    return depth

def main():
    frames = load_frames()
    print("frames", frames.shape, flush=True)
    if os.path.exists(f"{OUT}/tos_depth.npy"):
        depth = torch.from_numpy(np.load(f"{OUT}/tos_depth.npy").astype(np.float32))
        print("depth (cached)", depth.shape, flush=True)
    else:
        depth = get_depth(frames)  # [N,1,H,W] presumably 0..1 disparity-ish
        print("depth", depth.shape, float(depth.min()), float(depth.max()), flush=True)
        np.save(f"{OUT}/tos_depth.npy", depth.numpy().astype(np.float16))
    # iw3 default (ema_normalize=False, SimpleMinMaxScaler): per-frame independent minmax to [0,1]
    mins = depth.amin(dim=(2, 3), keepdim=True); maxs = depth.amax(dim=(2, 3), keepdim=True)
    depth = ((depth - mins) / (maxs - mins).clamp_min(1e-9)).clamp(0, 1)
    print("depth normalized", float(depth.min()), float(depth.max()), flush=True)
    if depth.shape[-2:] != (H, W):
        depth = torch.nn.functional.interpolate(depth, size=(H, W), mode="bilinear", align_corners=False)
        print("depth resized to", depth.shape, flush=True)

    from iw3.stereo_model_factory import create_stereo_model
    from iw3.backward_warp import apply_divergence_nn_LR

    DIV, CONV = 2.0, 1.0
    # T3: row_flow_v3
    rf = create_stereo_model("row_flow_v3", divergence=DIV, device_id=-1)
    with torch.inference_mode():
        lefts, rights = [], []
        for i in range(frames.shape[0]):
            l, r = apply_divergence_nn_LR(rf, frames[i:i+1], depth[i:i+1], DIV, CONV, 1,
                                          synthetic_view="both", preserve_screen_border=False, enable_amp=False)
            lefts.append(l); rights.append(r)
    save_sbs(torch.cat(lefts), torch.cat(rights), "tos_t3_row_flow_v3")
    del rf, lefts, rights; gc.collect()
    print("T3 done", flush=True)

    # T1: mlbw_l2_inpaint video
    mi = create_stereo_model("mlbw_l2_inpaint", divergence=DIV, device_id=-1)
    mi.set_mode("video")
    with torch.inference_mode():
        lefts, rights = [], []
        for i in range(frames.shape[0]):
            ret = mi.infer(frames[i:i+1], depth[i:i+1], divergence=DIV, convergence=CONV,
                           preserve_screen_border=False, synthetic_view="both",
                           inner_dilation=0, outer_dilation=0, max_width=None, enable_amp=False, alpha=None)
            if ret[0] is not None:
                lefts.append(ret[0]); rights.append(ret[1])
        ret = mi.flush(enable_amp=False)
        if ret[0] is not None:
            lefts.append(ret[0]); rights.append(ret[1])
    save_sbs(torch.cat(lefts), torch.cat(rights), "tos_t1_mlbw_l2_inpaint_video")
    n_t1 = torch.cat(lefts).shape[0]
    del mi, lefts, rights; gc.collect()
    print("T1 done, frames:", n_t1, flush=True)

    # T2: mlbw_l2_inpaint image on the still
    img = load_frame()
    with torch.inference_mode():
        d0 = depth[0:1]
    mi2 = create_stereo_model("mlbw_l2_inpaint", divergence=DIV, device_id=-1)
    mi2.set_mode("image")
    with torch.inference_mode():
        ret = mi2.infer(img, d0, divergence=DIV, convergence=CONV,
                        preserve_screen_border=False, synthetic_view="both",
                        inner_dilation=0, outer_dilation=0, max_width=None, enable_amp=False, alpha=None)
    l, r = ret[0], ret[1]
    save_sbs(l if l.ndim == 4 else l.unsqueeze(0), r if r.ndim == 4 else r.unsqueeze(0), "tos_t2_mlbw_l2_inpaint_image")
    print("T2 done", flush=True)

if __name__ == "__main__":
    main()
