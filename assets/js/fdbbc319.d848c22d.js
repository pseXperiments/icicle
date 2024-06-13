"use strict";(self.webpackChunkdocusaurus=self.webpackChunkdocusaurus||[]).push([[981],{5680:(e,t,n)=>{n.d(t,{xA:()=>c,yg:()=>d});var r=n(6540);function a(e,t,n){return t in e?Object.defineProperty(e,t,{value:n,enumerable:!0,configurable:!0,writable:!0}):e[t]=n,e}function i(e,t){var n=Object.keys(e);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(e);t&&(r=r.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),n.push.apply(n,r)}return n}function o(e){for(var t=1;t<arguments.length;t++){var n=null!=arguments[t]?arguments[t]:{};t%2?i(Object(n),!0).forEach((function(t){a(e,t,n[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(n)):i(Object(n)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(n,t))}))}return e}function l(e,t){if(null==e)return{};var n,r,a=function(e,t){if(null==e)return{};var n,r,a={},i=Object.keys(e);for(r=0;r<i.length;r++)n=i[r],t.indexOf(n)>=0||(a[n]=e[n]);return a}(e,t);if(Object.getOwnPropertySymbols){var i=Object.getOwnPropertySymbols(e);for(r=0;r<i.length;r++)n=i[r],t.indexOf(n)>=0||Object.prototype.propertyIsEnumerable.call(e,n)&&(a[n]=e[n])}return a}var u=r.createContext({}),s=function(e){var t=r.useContext(u),n=t;return e&&(n="function"==typeof e?e(t):o(o({},t),e)),n},c=function(e){var t=s(e.components);return r.createElement(u.Provider,{value:t},e.children)},p="mdxType",g={inlineCode:"code",wrapper:function(e){var t=e.children;return r.createElement(r.Fragment,{},t)}},m=r.forwardRef((function(e,t){var n=e.components,a=e.mdxType,i=e.originalType,u=e.parentName,c=l(e,["components","mdxType","originalType","parentName"]),p=s(n),m=a,d=p["".concat(u,".").concat(m)]||p[m]||g[m]||i;return n?r.createElement(d,o(o({ref:t},c),{},{components:n})):r.createElement(d,o({ref:t},c))}));function d(e,t){var n=arguments,a=t&&t.mdxType;if("string"==typeof e||a){var i=n.length,o=new Array(i);o[0]=m;var l={};for(var u in t)hasOwnProperty.call(t,u)&&(l[u]=t[u]);l.originalType=e,l[p]="string"==typeof e?e:a,o[1]=l;for(var s=2;s<i;s++)o[s]=n[s];return r.createElement.apply(null,o)}return r.createElement.apply(null,n)}m.displayName="MDXCreateElement"},2346:(e,t,n)=>{n.r(t),n.d(t,{assets:()=>u,contentTitle:()=>o,default:()=>g,frontMatter:()=>i,metadata:()=>l,toc:()=>s});var r=n(8168),a=(n(6540),n(5680));n(1873);const i={},o="Contributor's Guide",l={unversionedId:"contributor-guide",id:"contributor-guide",title:"Contributor's Guide",description:"We welcome all contributions with open arms. At Ingonyama we take a village approach, believing it takes many hands and minds to build a ecosystem.",source:"@site/docs/contributor-guide.md",sourceDirName:".",slug:"/contributor-guide",permalink:"/contributor-guide",editUrl:"https://github.com/ingonyama-zk/icicle/tree/main/docs/contributor-guide.md",tags:[],version:"current",lastUpdatedBy:"cangqiaoyuzhuo",lastUpdatedAt:1718268802,formattedLastUpdatedAt:"6/13/2024",frontMatter:{},sidebar:"GettingStartedSidebar",previous:{title:"Ingonyama Grant programs",permalink:"/grants"}},u={},s=[{value:"Contributing to ICICLE",id:"contributing-to-icicle",level:2},{value:"Opening a pull request",id:"opening-a-pull-request",level:3},{value:"Questions?",id:"questions",level:2}],c={toc:s},p="wrapper";function g(e){let{components:t,...n}=e;return(0,a.yg)(p,(0,r.A)({},c,n,{components:t,mdxType:"MDXLayout"}),(0,a.yg)("h1",{id:"contributors-guide"},"Contributor's Guide"),(0,a.yg)("p",null,"We welcome all contributions with open arms. At Ingonyama we take a village approach, believing it takes many hands and minds to build a ecosystem."),(0,a.yg)("h2",{id:"contributing-to-icicle"},"Contributing to ICICLE"),(0,a.yg)("ul",null,(0,a.yg)("li",{parentName:"ul"},"Make suggestions or report bugs via ",(0,a.yg)("a",{parentName:"li",href:"https://github.com/ingonyama-zk/icicle/issues"},"GitHub issues")),(0,a.yg)("li",{parentName:"ul"},"Contribute to the ICICLE by opening a ",(0,a.yg)("a",{parentName:"li",href:"https://github.com/ingonyama-zk/icicle/pulls"},"pull request"),"."),(0,a.yg)("li",{parentName:"ul"},"Contribute to our ",(0,a.yg)("a",{parentName:"li",href:"https://github.com/ingonyama-zk/icicle/tree/main/docs"},"documentation")," and ",(0,a.yg)("a",{parentName:"li",href:"https://github.com/ingonyama-zk/icicle/tree/main/examples"},"examples"),"."),(0,a.yg)("li",{parentName:"ul"},"Ask questions on Discord")),(0,a.yg)("h3",{id:"opening-a-pull-request"},"Opening a pull request"),(0,a.yg)("p",null,"When opening a ",(0,a.yg)("a",{parentName:"p",href:"https://github.com/ingonyama-zk/icicle/pulls"},"pull request")," please keep the following in mind."),(0,a.yg)("ul",null,(0,a.yg)("li",{parentName:"ul"},(0,a.yg)("inlineCode",{parentName:"li"},"Clear Purpose")," - The pull request should solve a single issue and be clean of any unrelated changes."),(0,a.yg)("li",{parentName:"ul"},(0,a.yg)("inlineCode",{parentName:"li"},"Clear description")," - If the pull request is for a new feature describe what you built, why you added it and how its best that we test it. For bug fixes please describe the issue and the solution."),(0,a.yg)("li",{parentName:"ul"},(0,a.yg)("inlineCode",{parentName:"li"},"Consistent style")," - Rust and Golang code should be linted by the official linters (golang fmt and rust fmt) and maintain a proper style. For CUDA and C++ code we use ",(0,a.yg)("a",{parentName:"li",href:"https://github.com/ingonyama-zk/icicle/blob/main/.clang-format"},(0,a.yg)("inlineCode",{parentName:"a"},"clang-format")),", ",(0,a.yg)("a",{parentName:"li",href:"https://github.com/ingonyama-zk/icicle/blob/605c25f9d22135c54ac49683b710fe2ce06e2300/.github/workflows/main-format.yml#L46"},"here")," you can see how we run it."),(0,a.yg)("li",{parentName:"ul"},(0,a.yg)("inlineCode",{parentName:"li"},"Minimal Tests")," - please add test which cover basic usage of your changes .")),(0,a.yg)("h2",{id:"questions"},"Questions?"),(0,a.yg)("p",null,"Find us on ",(0,a.yg)("a",{parentName:"p",href:"https://discord.gg/6vYrE7waPj"},"Discord"),"."))}g.isMDXComponent=!0},1873:(e,t,n)=>{n(6540)}}]);