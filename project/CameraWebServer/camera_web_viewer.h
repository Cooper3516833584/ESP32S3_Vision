#pragma once

// Self-contained browser viewer served by the ESP32. Raw frame header (RFS1,
// 20-byte little-endian header) and PackBits decoding mirror raw_frame_codec.h.
static const char CAMERA_WEB_VIEWER_HTML[] = R"HTML(<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ESP32-S3 Camera Viewer</title><style>
:root{color-scheme:dark;font:16px system-ui,sans-serif;background:#10151b;color:#e8eef5}body{max-width:900px;margin:24px auto;padding:0 16px}h1{font-size:1.5rem}button{padding:9px 14px;margin:4px;border:0;border-radius:6px;background:#2878d0;color:white;cursor:pointer}button.secondary{background:#495563}.status{padding:10px;background:#202a35;border-radius:6px;margin:12px 0}.dot{color:#9aa7b4}.ok{color:#62d394}.bad{color:#ff8585}.viewer{width:min(100%,640px);aspect-ratio:4/3;background:#000;display:block;image-rendering:pixelated}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:8px;margin:12px 0}.stat{background:#202a35;padding:9px;border-radius:5px}.stat b{display:block;color:#8ebfff;font-size:.82rem}.note{color:#b8c5d2;font-size:.92rem}
</style></head><body><h1>ESP32-S3 Camera Viewer</h1>
<p class="note">请连接 ESP32-S3 自建 Wi-Fi：<b>esp32s3cam-xxxx</b>，密码 11223344。默认地址 192.168.4.1。该网络没有 Internet 属于正常现象。</p>
<div class="status">连接状态：<span id="status" class="dot">正在连接 ESP32 视频流……</span></div>
<button id="reconnect">重新连接</button><button id="mode" class="secondary">切换到 MJPEG 兼容模式</button>
<canvas id="canvas" class="viewer" width="320" height="240"></canvas><img id="mjpeg" class="viewer" hidden alt="ESP32 摄像头视频">
<div class="stats"><div class="stat"><b>Stream FPS</b><span id="fps">--</span></div><div class="stat"><b>Processing FPS</b><span id="pfps">--</span></div><div class="stat"><b>Processing Time</b><span id="ptime">--</span></div><div class="stat"><b>Frame Bytes</b><span id="bytes">--</span></div><div class="stat"><b>Free Heap</b><span id="heap">--</span></div><div class="stat"><b>Free PSRAM</b><span id="psram">--</span></div></div>
<p class="note" id="debug"></p>
<script>
(()=>{
const canvas=document.getElementById('canvas'),ctx=canvas.getContext('2d',{alpha:false}),img=document.getElementById('mjpeg');
const statusEl=document.getElementById('status'),modeBtn=document.getElementById('mode'),debugEl=document.getElementById('debug');
let mode='raw',controller=null,retryTimer=null,runId=0,buffer=new Uint8Array(4096),head=0,used=0,rgba=new Uint8ClampedArray(320*240*4),imageData=new ImageData(rgba,320,240),rawPixels=new Uint8Array(320*240),decoded=0,dropped=0,errors=0;
const debug=new URLSearchParams(location.search).get('debug')==='1';
function state(text,kind='dot'){statusEl.textContent=text;statusEl.className=kind}
function stop(){runId++;if(retryTimer){clearTimeout(retryTimer);retryTimer=null}if(controller){controller.abort();controller=null}img.removeAttribute('src');head=0;used=0}
function schedule(id){if(id!==runId)return;retryTimer=setTimeout(()=>connect(),1500)}
function append(bytes){let remain=used-head,needed=remain+bytes.length;if(buffer.length-head<needed){const next=new Uint8Array(Math.max(needed,buffer.length*2));if(remain)next.set(buffer.subarray(head,used));buffer=next;head=0;used=remain}else if(head>0&&buffer.length-used<bytes.length){buffer.copyWithin(0,head,used);head=0;used=remain}buffer.set(bytes,used);used+=bytes.length}
function u16(p){return buffer[p]|(buffer[p+1]<<8)}function u32(p){return (buffer[p]|(buffer[p+1]<<8)|(buffer[p+2]<<16)|(buffer[p+3]<<24))>>>0}
function decode(payload,n){let s=0,d=0;while(s<payload.length&&d<n){const control=payload[s++],len=(control&127)+1;if(control&128){if(s>=payload.length||d+len>n)return false;rawPixels.fill(payload[s++],d,d+len);d+=len}else{if(s+len>payload.length||d+len>n)return false;rawPixels.set(payload.subarray(s,s+len),d);s+=len;d+=len}}return d===n&&s===payload.length}
function parse(){while(used-head>=4){if(buffer[head]!==82||buffer[head+1]!==70||buffer[head+2]!==83||buffer[head+3]!==49){let found=-1;for(let i=head+1;i+3<used;i++){if(buffer[i]===82&&buffer[i+1]===70&&buffer[i+2]===83&&buffer[i+3]===49){found=i;break}}if(found<0){head=Math.max(head,used-3);errors++;return}head=found;errors++;continue}
if(used-head<20)return;const w=u16(head+6),h=u16(head+8),len=u32(head+10);const max=76800+Math.ceil(76800/128)+16;if(buffer[head+4]!==3||!w||!h||w>320||h>240||w*h>76800||len<1||len>max){head++;errors++;continue}if(used-head<20+len)return;const pixels=w*h,ok=decode(buffer.subarray(head+20,head+20+len),pixels);head+=20+len;if(!ok){dropped++;continue}if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;rgba=new Uint8ClampedArray(pixels*4);imageData=new ImageData(rgba,w,h)}for(let i=0,j=0;i<pixels;i++,j+=4){const v=rawPixels[i];rgba[j]=((v>>5)&7)*255/7;rgba[j+1]=((v>>2)&7)*255/7;rgba[j+2]=(v&3)*255/3;rgba[j+3]=255}ctx.putImageData(imageData,0,0);decoded++}
if(head===used){head=0;used=0}else if(head>65536){used=used-head;buffer.copyWithin(0,head,head+used);head=0}}
async function rawLoop(id){controller=new AbortController();try{const host=location.hostname;const response=await fetch(`http://${host}:81/raw`,{cache:'no-store',signal:controller.signal});if(response.status===503){state('已有其他 Viewer 占用。请关闭 CameraStreamViewer.exe 或其他视频标签页，再重新连接。','bad');throw Error('occupied')}if(!response.ok)throw Error('HTTP '+response.status);if(!response.body||!response.body.getReader){state('当前浏览器不支持 Raw 流，请切换到 MJPEG 兼容模式。','bad');mode='mjpeg';updateMode();return connect()}state('视频流已连接','ok');const reader=response.body.getReader();while(id===runId){const part=await reader.read();if(part.done)break;append(part.value);parse()}throw Error('stream ended')}catch(e){if(id!==runId||e.name==='AbortError')return;if(e.message!=='occupied')state('视频流已断开，正在重新连接……','bad');schedule(id)}}
function connect(){stop();const id=runId;canvas.hidden=mode!=='raw';img.hidden=mode!=='mjpeg';if(mode==='mjpeg'){state('正在连接 MJPEG 兼容流……');fetch('/metrics',{cache:'no-store'}).then(r=>r.json()).then(m=>{if(id!==runId)return;if(m.stream_active){state('已有其他 Viewer 占用。请关闭 CameraStreamViewer.exe 或其他视频标签页，再点击重新连接。','bad');schedule(id);return}img.onerror=()=>{if(id===runId){state('MJPEG 连接失败。请检查 Wi-Fi，或确认没有其他 Viewer 占用。','bad');schedule(id)}};img.onload=()=>{if(id===runId)state('视频流已连接（MJPEG）','ok')};img.src=`http://${location.hostname}:81/stream?nocache=${Date.now()}`}).catch(()=>{if(id===runId){img.src=`http://${location.hostname}:81/stream?nocache=${Date.now()}`}});return}state('正在连接 ESP32 视频流……');rawLoop(id)}
function updateMode(){modeBtn.textContent=mode==='raw'?'切换到 MJPEG 兼容模式':'切换到 Raw 低延迟模式'}
document.getElementById('reconnect').onclick=()=>connect();modeBtn.onclick=()=>{mode=mode==='raw'?'mjpeg':'raw';updateMode();connect()};
async function metrics(){try{const r=await fetch('/metrics',{cache:'no-store'});if(!r.ok)throw 0;const m=await r.json();document.getElementById('fps').textContent=m.fps+' fps';document.getElementById('pfps').textContent=m.processing_fps+' fps';document.getElementById('ptime').textContent=m.last_processing_ms+' ms';document.getElementById('bytes').textContent=m.last_frame_bytes+' B';document.getElementById('heap').textContent=m.free_heap+' B';document.getElementById('psram').textContent=m.free_psram+' B'}catch(_){}}
setInterval(metrics,1000);setInterval(()=>{if(debug)debugEl.textContent=`Decoded frames: ${decoded} · Dropped: ${dropped} · Protocol errors: ${errors}`},1000);metrics();updateMode();connect();
})();
</script></body></html>)HTML";
