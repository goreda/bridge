import { a } from "./mod1.js?v=2";
import "./mod2.js";
import "https://external.example/x.js";
import "./missing.js";
console.log(a);
