const api=globalThis.browser??globalThis.chrome;
const fields=['endpoint','token','browser'];
api.storage.local.get(fields).then(values=>fields.forEach(key=>{if(values[key])document.getElementById(key).value=values[key];}));
document.getElementById('save').onclick=async()=>{
 const values=Object.fromEntries(fields.map(key=>[key,document.getElementById(key).value.trim()]));
 const url=new URL(values.endpoint);
 if(url.protocol!=='ws:'||url.hostname!=='127.0.0.1'||!/^[a-f0-9]{64}$/.test(values.token)){document.getElementById('status').textContent='앱의 연결 주소와 코드를 확인하세요.';return;}
 await api.storage.local.set(values);document.getElementById('status').textContent='저장했습니다. 앱에서 연결 상태를 확인하세요.';
};
