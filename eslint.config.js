import js from '@eslint/js';
import globals from 'globals';
import react from 'eslint-plugin-react';
export default [{ignores:['dist/**','node_modules/**','dfab-erp-final/**']},{files:['src/**/*.{js,jsx}'],languageOptions:{ecmaVersion:'latest',sourceType:'module',parserOptions:{ecmaFeatures:{jsx:true}},globals:globals.browser},plugins:{react},rules:{'no-undef':'error','no-unreachable':'error','no-dupe-args':'error','no-dupe-keys':'error','valid-typeof':'error','react/jsx-no-undef':'error'}},js.configs.recommended && {files:['tests/**/*.js'],languageOptions:{globals:{...globals.node,...globals.browser}},rules:{'no-undef':'error'}}];
