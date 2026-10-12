const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname);
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json; charset=utf-8','.png':'image/png','.svg':'image/svg+xml'};
http.createServer((req,res)=>{
 let pathname; try {pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname)}catch {res.writeHead(400);res.end();return}
 const file=path.resolve(root,'.'+(pathname==='/'?'/index.html':pathname));
 if(file!==root&&!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return}
 fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end('Not found');return}res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(data)})
}).listen(4173,'127.0.0.1',()=>console.log('UI design: http://127.0.0.1:4173'));
