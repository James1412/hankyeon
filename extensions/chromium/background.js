import {createMediaService} from './media/media-service.js';
import {createMediaTracker} from './media/media-tracker.js';
const api = globalThis.browser ?? globalThis.chrome;
let socket;
let authenticated = false;
let reconnect;
let heartbeat;
let config;
const transport = {
  tabs: api.tabs,
  scripting: api.scripting,
  runtime: {
    sendMessage: message => api.runtime.sendMessage(message),
    sendNativeMessage: async (_, message) => {
      if (!authenticated || socket?.readyState !== WebSocket.OPEN) return {ok:false};
      socket.send(JSON.stringify({type:'snapshot',browser:config.browser,mediaList:message.mediaList}));
      return {ok:true};
    },
  },
};
const service = createMediaService(transport);
const tracker = createMediaTracker(api, service);
async function connect() {
  clearTimeout(reconnect); clearInterval(heartbeat);
  config = await api.storage.local.get(['endpoint','token','clientId','browser']);
  if (!config.token) return;
  if (!config.clientId) { config.clientId = crypto.randomUUID(); await api.storage.local.set({clientId:config.clientId}); }
  const url = new URL(config.endpoint || 'ws://127.0.0.1:43127');
  if (url.hostname !== '127.0.0.1' || url.protocol !== 'ws:') return;
  const previous = socket; if(previous) previous.onclose = null; previous?.close();
  authenticated = false;
  socket = new WebSocket(url);
  socket.onopen = () => socket.send(JSON.stringify({type:'hello',token:config.token,clientId:config.clientId}));
  socket.onmessage = async event => {
    try {
      const message = JSON.parse(event.data);
      if (message.type === 'connected') { authenticated=true; heartbeat=setInterval(()=>{if(socket?.readyState===WebSocket.OPEN)socket.send(JSON.stringify({type:'ping'}));},20000); await tracker.listMedia(); return; }
      if (!authenticated || message.type !== 'command') return;
      let result;
      try {
        result = message.action === 'refresh' ? await tracker.listMedia() : await service.controlMedia(message);
        if(message.action !== 'refresh') tracker.refreshTab(message.tabId).catch(console.error);
      } catch(error) { result={ok:false,error:String(error)}; }
      socket.send(JSON.stringify({type:'result',requestId:message.requestId,ok:result.ok !== false,error:result.error}));
    } catch(error) { console.error(String(error)); }
  };
  socket.onclose = () => {clearInterval(heartbeat); authenticated=false; reconnect=setTimeout(connect,3000);};
  socket.onerror = () => socket.close();
}
api.runtime.onMessage.addListener((message,sender,respond) => {
  if(message?.type !== 'hankyeon-media-changed' || sender.id !== api.runtime.id || sender.url !== message.documentUrl || !Number.isInteger(sender.tab?.id)) return;
  tracker.refreshTab(sender.tab.id).then(()=>respond({ok:true}),error=>respond({ok:false,error:String(error)}));return true;
});
api.tabs.onUpdated.addListener((id,change)=>{if(change.status==='complete'||change.url||change.title)tracker.refreshTab(id).catch(console.error);});
api.tabs.onRemoved.addListener(id=>tracker.removeTab(id).catch(console.error));
api.tabs.onMoved.addListener(()=>tracker.updateOrder().catch(console.error));
api.storage.onChanged.addListener(changes=>{if(['endpoint','token','browser'].some(key=>key in changes))connect().catch(console.error);});
connect().catch(console.error);
