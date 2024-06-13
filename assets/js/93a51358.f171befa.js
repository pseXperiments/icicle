"use strict";(self.webpackChunkdocusaurus=self.webpackChunkdocusaurus||[]).push([[966],{5680:(e,t,n)=>{n.d(t,{xA:()=>o,yg:()=>y});var r=n(6540);function a(e,t,n){return t in e?Object.defineProperty(e,t,{value:n,enumerable:!0,configurable:!0,writable:!0}):e[t]=n,e}function i(e,t){var n=Object.keys(e);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(e);t&&(r=r.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),n.push.apply(n,r)}return n}function l(e){for(var t=1;t<arguments.length;t++){var n=null!=arguments[t]?arguments[t]:{};t%2?i(Object(n),!0).forEach((function(t){a(e,t,n[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(n)):i(Object(n)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(n,t))}))}return e}function g(e,t){if(null==e)return{};var n,r,a=function(e,t){if(null==e)return{};var n,r,a={},i=Object.keys(e);for(r=0;r<i.length;r++)n=i[r],t.indexOf(n)>=0||(a[n]=e[n]);return a}(e,t);if(Object.getOwnPropertySymbols){var i=Object.getOwnPropertySymbols(e);for(r=0;r<i.length;r++)n=i[r],t.indexOf(n)>=0||Object.prototype.propertyIsEnumerable.call(e,n)&&(a[n]=e[n])}return a}var c=r.createContext({}),p=function(e){var t=r.useContext(c),n=t;return e&&(n="function"==typeof e?e(t):l(l({},t),e)),n},o=function(e){var t=p(e.components);return r.createElement(c.Provider,{value:t},e.children)},d="mdxType",s={inlineCode:"code",wrapper:function(e){var t=e.children;return r.createElement(r.Fragment,{},t)}},u=r.forwardRef((function(e,t){var n=e.components,a=e.mdxType,i=e.originalType,c=e.parentName,o=g(e,["components","mdxType","originalType","parentName"]),d=p(n),u=a,y=d["".concat(c,".").concat(u)]||d[u]||s[u]||i;return n?r.createElement(y,l(l({ref:t},o),{},{components:n})):r.createElement(y,l({ref:t},o))}));function y(e,t){var n=arguments,a=t&&t.mdxType;if("string"==typeof e||a){var i=n.length,l=new Array(i);l[0]=u;var g={};for(var c in t)hasOwnProperty.call(t,c)&&(g[c]=t[c]);g.originalType=e,g[d]="string"==typeof e?e:a,l[1]=g;for(var p=2;p<i;p++)l[p]=n[p];return r.createElement.apply(null,l)}return r.createElement.apply(null,n)}u.displayName="MDXCreateElement"},3703:(e,t,n)=>{n.r(t),n.d(t,{assets:()=>c,contentTitle:()=>l,default:()=>s,frontMatter:()=>i,metadata:()=>g,toc:()=>p});var r=n(8168),a=(n(6540),n(5680));n(1873);const i={},l="Rust bindings",g={unversionedId:"icicle/rust-bindings",id:"icicle/rust-bindings",title:"Rust bindings",description:"Rust bindings allow you to use ICICLE as a rust library.",source:"@site/docs/icicle/rust-bindings.md",sourceDirName:"icicle",slug:"/icicle/rust-bindings",permalink:"/icicle/rust-bindings",editUrl:"https://github.com/ingonyama-zk/icicle/tree/main/docs/icicle/rust-bindings.md",tags:[],version:"current",lastUpdatedBy:"cangqiaoyuzhuo",lastUpdatedAt:1718268802,formattedLastUpdatedAt:"6/13/2024",frontMatter:{},sidebar:"GettingStartedSidebar",previous:{title:"Multi GPU APIs",permalink:"/icicle/golang-bindings/multi-gpu"},next:{title:"MSM",permalink:"/icicle/rust-bindings/msm"}},c={},p=[{value:"Using ICICLE Rust bindings in your project",id:"using-icicle-rust-bindings-in-your-project",level:2},{value:"How do the rust bindings work?",id:"how-do-the-rust-bindings-work",level:2},{value:"Supported curves, fields and operations",id:"supported-curves-fields-and-operations",level:2},{value:"Supported curves and operations",id:"supported-curves-and-operations",level:3},{value:"Supported fields and operations",id:"supported-fields-and-operations",level:3},{value:"Supported hashes",id:"supported-hashes",level:3}],o={toc:p},d="wrapper";function s(e){let{components:t,...n}=e;return(0,a.yg)(d,(0,r.A)({},o,n,{components:t,mdxType:"MDXLayout"}),(0,a.yg)("h1",{id:"rust-bindings"},"Rust bindings"),(0,a.yg)("p",null,"Rust bindings allow you to use ICICLE as a rust library."),(0,a.yg)("p",null,(0,a.yg)("inlineCode",{parentName:"p"},"icicle-core")," defines all interfaces, macros and common methods."),(0,a.yg)("p",null,(0,a.yg)("inlineCode",{parentName:"p"},"icicle-cuda-runtime")," defines DeviceContext which can be used to manage a specific GPU as well as wrapping common CUDA methods."),(0,a.yg)("p",null,(0,a.yg)("inlineCode",{parentName:"p"},"icicle-curves")," implements all interfaces and macros from icicle-core for each curve. For example icicle-bn254 implements curve bn254. Each curve has its own build script which will build the CUDA libraries for that curve as part of the rust-toolchain build."),(0,a.yg)("h2",{id:"using-icicle-rust-bindings-in-your-project"},"Using ICICLE Rust bindings in your project"),(0,a.yg)("p",null,"Simply add the following to your ",(0,a.yg)("inlineCode",{parentName:"p"},"Cargo.toml"),"."),(0,a.yg)("pre",null,(0,a.yg)("code",{parentName:"pre",className:"language-toml"},'# GPU Icicle integration\nicicle-cuda-runtime = { git = "https://github.com/ingonyama-zk/icicle.git" }\nicicle-core = { git = "https://github.com/ingonyama-zk/icicle.git" }\nicicle-bn254 = { git = "https://github.com/ingonyama-zk/icicle.git" }\n')),(0,a.yg)("p",null,(0,a.yg)("inlineCode",{parentName:"p"},"icicle-bn254")," being the curve you wish to use and ",(0,a.yg)("inlineCode",{parentName:"p"},"icicle-core")," and ",(0,a.yg)("inlineCode",{parentName:"p"},"icicle-cuda-runtime")," contain ICICLE utilities and CUDA wrappers."),(0,a.yg)("p",null,"If you wish to point to a specific ICICLE branch add ",(0,a.yg)("inlineCode",{parentName:"p"},'branch = "<name_of_branch>"')," or ",(0,a.yg)("inlineCode",{parentName:"p"},'tag = "<name_of_tag>"')," to the ICICLE dependency. For a specific commit add ",(0,a.yg)("inlineCode",{parentName:"p"},'rev = "<commit_id>"'),"."),(0,a.yg)("p",null,"When you build your project ICICLE will be built as part of the build command."),(0,a.yg)("h2",{id:"how-do-the-rust-bindings-work"},"How do the rust bindings work?"),(0,a.yg)("p",null,"The rust bindings are just rust wrappers for ICICLE Core static libraries which can be compiled. We integrate the compilation of the static libraries into rusts toolchain to make usage seamless and easy. This is achieved by ",(0,a.yg)("a",{parentName:"p",href:"https://github.com/ingonyama-zk/icicle/blob/main/wrappers/rust/icicle-curves/icicle-bn254/build.rs"},"extending rusts build command"),"."),(0,a.yg)("pre",null,(0,a.yg)("code",{parentName:"pre",className:"language-rust"},'use cmake::Config;\nuse std::env::var;\n\nfn main() {\n    println!("cargo:rerun-if-env-changed=CXXFLAGS");\n    println!("cargo:rerun-if-changed=../../../../icicle");\n\n    let cargo_dir = var("CARGO_MANIFEST_DIR").unwrap();\n    let profile = var("PROFILE").unwrap();\n\n    let out_dir = Config::new("../../../../icicle")\n                .define("BUILD_TESTS", "OFF") //TODO: feature\n                .define("CURVE", "bn254")\n                .define("CMAKE_BUILD_TYPE", "Release")\n                .build_target("icicle")\n                .build();\n\n    println!("cargo:rustc-link-search={}/build", out_dir.display());\n\n    println!("cargo:rustc-link-lib=ingo_bn254");\n    println!("cargo:rustc-link-lib=stdc++");\n    // println!("cargo:rustc-link-search=native=/usr/local/cuda/lib64");\n    println!("cargo:rustc-link-lib=cudart");\n}\n')),(0,a.yg)("h2",{id:"supported-curves-fields-and-operations"},"Supported curves, fields and operations"),(0,a.yg)("h3",{id:"supported-curves-and-operations"},"Supported curves and operations"),(0,a.yg)("table",null,(0,a.yg)("thead",{parentName:"table"},(0,a.yg)("tr",{parentName:"thead"},(0,a.yg)("th",{parentName:"tr",align:null},"Operation\\Curve"),(0,a.yg)("th",{parentName:"tr",align:"center"},"bn254"),(0,a.yg)("th",{parentName:"tr",align:"center"},"bls12_377"),(0,a.yg)("th",{parentName:"tr",align:"center"},"bls12_381"),(0,a.yg)("th",{parentName:"tr",align:"center"},"bw6-761"),(0,a.yg)("th",{parentName:"tr",align:"center"},"grumpkin"))),(0,a.yg)("tbody",{parentName:"table"},(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"MSM"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"G2"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u274c")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"NTT"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u274c")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"ECNTT"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u274c")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"VecOps"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"Polynomials"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u274c")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"Poseidon"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"Merkle Tree"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705")))),(0,a.yg)("h3",{id:"supported-fields-and-operations"},"Supported fields and operations"),(0,a.yg)("table",null,(0,a.yg)("thead",{parentName:"table"},(0,a.yg)("tr",{parentName:"thead"},(0,a.yg)("th",{parentName:"tr",align:null},"Operation\\Field"),(0,a.yg)("th",{parentName:"tr",align:"center"},"babybear"),(0,a.yg)("th",{parentName:"tr",align:"center"},"stark252"))),(0,a.yg)("tbody",{parentName:"table"},(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"VecOps"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"Polynomials"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"NTT"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705")),(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"Extension Field"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u2705"),(0,a.yg)("td",{parentName:"tr",align:"center"},"\u274c")))),(0,a.yg)("h3",{id:"supported-hashes"},"Supported hashes"),(0,a.yg)("table",null,(0,a.yg)("thead",{parentName:"table"},(0,a.yg)("tr",{parentName:"thead"},(0,a.yg)("th",{parentName:"tr",align:null},"Hash"),(0,a.yg)("th",{parentName:"tr",align:"center"},"Sizes"))),(0,a.yg)("tbody",{parentName:"table"},(0,a.yg)("tr",{parentName:"tbody"},(0,a.yg)("td",{parentName:"tr",align:null},"Keccak"),(0,a.yg)("td",{parentName:"tr",align:"center"},"256, 512")))))}s.isMDXComponent=!0},1873:(e,t,n)=>{n(6540)}}]);