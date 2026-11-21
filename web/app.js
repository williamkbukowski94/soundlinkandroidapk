const status=document.querySelector('#release-status');
async function loadRelease(){
 try{
  const config=await (await fetch('./config.json')).json();
  const endpoint=new URL('/rest/v1/soundlink_releases',config.supabaseUrl);
  endpoint.search=new URLSearchParams({select:'version,channel,filename,download_url,size_bytes,min_android,sha256',published:'eq.true',order:'published_at.desc',limit:'1'});
  const response=await fetch(endpoint,{headers:{apikey:config.supabaseKey},signal:AbortSignal.timeout(7000)});
  if(!response.ok)throw new Error('Release lookup unavailable');
  const [release]=await response.json();
  if(!release||!/^[a-f0-9]{64}$/.test(release.sha256)||!/^\d+\.\d+\.\d+$/.test(release.version))throw new Error('Invalid release');
  const download=new URL(release.download_url);
  if(download.protocol!=='https:'||download.hostname!=='github.com'||!download.pathname.startsWith('/williamkbukowski94/soundlinkandroidapk/releases/download/'))throw new Error('Invalid download location');
  document.querySelectorAll('.download-link,.card-download').forEach(link=>link.href=download.href);
  document.querySelector('#version').textContent=release.version;
  document.querySelector('#size').textContent=`${(release.size_bytes/1024).toFixed(0)} KB`;
  document.querySelector('#android').textContent=release.min_android;
  document.querySelector('#checksum').textContent=release.sha256;
  status.textContent=`Version ${release.version} · ${(release.size_bytes/1024).toFixed(0)} KB · Android ${release.min_android}+`;
 }catch{
  status.textContent='Version 0.1.0 · GitHub download available; live release details unavailable.';
 }
}
loadRelease();
document.querySelector('#copy-checksum').addEventListener('click',async()=>{
 const label=document.querySelector('#copy-status');
 try{await navigator.clipboard.writeText(document.querySelector('#checksum').textContent);label.textContent='Copied';}catch{label.textContent='Select the checksum above to copy it.';}
});
