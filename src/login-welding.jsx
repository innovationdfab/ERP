import React from 'react';

const sparks=[[-155,42],[-128,64],[-96,50],[-65,76],[-33,56],[8,66],[34,90],[57,68],[83,84],[112,56],[142,72],[170,46]];

export function LoginWelding({active,onToggle}){
  return <section className={`dfab-torch-scene login-welding-scene ${active?'is-welding':''}`} aria-label="Interactive welding torch">
    <button type="button" className="login-weld-control" onClick={onToggle} aria-pressed={active}
      title={active?'Stop welding':'Start welding'} aria-label={active?'Stop welding':'Start welding'}>
      <svg viewBox="0 0 600 460" aria-hidden="true" focusable="false">
        <defs>
          <linearGradient id="login-steel" x1="0" y1="0" x2="0" y2="1"><stop stopColor="#849baa"/><stop offset=".22" stopColor="#c9d6df"/><stop offset=".3" stopColor="#576d7f"/><stop offset="1" stopColor="#243a4c"/></linearGradient>
          <linearGradient id="login-grip" x1="0" y1="0" x2="1" y2="1"><stop stopColor="#536c80"/><stop offset=".45" stopColor="#273b4c"/><stop offset="1" stopColor="#101d2a"/></linearGradient>
          <linearGradient id="login-metal" x1="0" y1="0" x2="0" y2="1"><stop stopColor="#d9e5ec"/><stop offset=".35" stopColor="#9dafbe"/><stop offset=".65" stopColor="#465e72"/><stop offset="1" stopColor="#bccbd7"/></linearGradient>
          <linearGradient id="login-copper" x1="0" y1="0" x2="1" y2="1"><stop stopColor="#f1bf84"/><stop offset=".4" stopColor="#c9844f"/><stop offset="1" stopColor="#6e3d25"/></linearGradient>
          <radialGradient id="login-arc-light"><stop stopColor="#e6faff" stopOpacity=".8"/><stop offset=".2" stopColor="#79d9ff" stopOpacity=".45"/><stop offset="1" stopColor="#52b6ff" stopOpacity="0"/></radialGradient>
        </defs>
        <g className="weld-workbench">
          <ellipse cx="305" cy="344" rx="224" ry="27" fill="#020a12" opacity=".5"/>
          <path d="M72 281 L516 281 L544 307 L97 307 Z" fill="url(#login-steel)"/>
          <path d="M97 307 L544 307 L544 326 L97 326 Z" fill="#24394a"/>
          <path d="M72 281 L97 307 L97 326 L72 301 Z" fill="#455e70"/>
          <path d="M90 282 L510 282" stroke="#d6e5ef" strokeOpacity=".55"/>
          <path d="M161 292 L489 292" stroke="#112535" strokeWidth="5"/>
          <path className="weld-finished-seam" d="M161 292 L434 292" fill="none" stroke="#c99766" strokeWidth="4" strokeLinecap="round"/>
          <path d="M121 317 L513 317" stroke="#526b7f" strokeOpacity=".5"/>
        </g>
        <g className="weld-pass">
          <circle className="weld-light" cx="391" cy="288" r="128" fill="url(#login-arc-light)"/>
          <g className="weld-gun">
            <path d="M54 415 C15 367 32 310 114 293" stroke="#0a1420" strokeWidth="22" fill="none" strokeLinecap="round"/>
            <path d="M54 415 C15 367 32 310 114 293" stroke="#344b5e" strokeWidth="13" fill="none" strokeLinecap="round"/>
            <path d="M103 275 L166 233 Q180 225 191 239 L222 280 Q229 292 215 303 L151 344 Q135 353 124 338 L94 297 Q86 283 103 275 Z" fill="url(#login-grip)" stroke="#688299" strokeWidth="1.5"/>
            <path d="M113 288 L165 253 M124 305 L178 269 M136 323 L189 286" stroke="#0c1925" strokeWidth="6" strokeLinecap="round"/>
            <path d="M173 257 L195 242 L209 261 L187 277 Z" fill="#78a9c9"/>
            <path d="M187 237 C225 207 248 190 275 211 L346 256" stroke="#243c50" strokeWidth="27" fill="none" strokeLinecap="round"/>
            <path d="M187 232 C225 202 248 185 275 206 L346 251" stroke="url(#login-metal)" strokeWidth="19" fill="none" strokeLinecap="round"/>
            <path d="M330 233 L384 267 L369 289 L316 255 Z" fill="url(#login-copper)" stroke="#e5b07c" strokeWidth="1"/>
            <path d="M378 272 L391 282 L387 290 L373 280 Z" fill="url(#login-metal)"/>
            <path d="M389 286 L394 293" stroke="#efb67c" strokeWidth="2"/>
          </g>
          <g className="weld-active-effects">
            <circle className="weld-soft-halo" cx="392" cy="291" r="33" fill="url(#login-arc-light)"/>
            <ellipse className="weld-arc-core" cx="392" cy="291" rx="7" ry="5" fill="#effcff"/>
            {sparks.map(([angle,length],index)=><line key={angle} className="weld-particle" x1="402" y1="291" x2={402+length} y2="291"
              transform={`rotate(${angle} 392 291)`} style={{'--spark-delay':`${index*-.17}s`,'--spark-duration':`${1.1+(index%4)*.16}s`}}/>) }
            <path className="weld-smoke smoke-one" d="M391 277 C370 251 413 235 392 207 C372 179 406 170 398 143"/>
            <path className="weld-smoke smoke-two" d="M398 276 C418 255 389 239 405 219 C429 187 401 174 414 153"/>
          </g>
        </g>
      </svg>
      <span className="login-weld-caption"><span className="login-weld-indicator"/>{active?'Welding active · Sign in to continue':'Start welding to unlock sign in'}</span>
    </button>
  </section>;
}
