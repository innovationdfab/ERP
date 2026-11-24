import React from 'react';
export function DateInput({onChange,...props}){return <input {...props} onChange={onChange} onInput={onChange}/>;}
