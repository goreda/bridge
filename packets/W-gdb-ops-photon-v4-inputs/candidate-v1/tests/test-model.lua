local m=dofile('photon-v4/lua/photon-v4-model.lua')
for _,src in ipairs{480,720,1080,2160} do
 for _,out in ipairs{1080,1440,2160} do
  for _,cell in ipairs{0.4,0.8,1.2,2,5} do
   print(string.format('cell %.12f',m.cell(src,out,cell,1,0.8/1080,1)))
  end
 end
end
for _,t in ipairs{0.0015,0.003,0.01,0.02} do
 for _,s in ipairs{0,0.001,0.01,0.04} do
  for _,c in ipairs{1,1.5,2} do
   local v=m.sigma(t,s,0.35,c,1,1,true)
   assert(v>0 and v>=0.35*t*c-1e-16)
   print(string.format('sigma %.12f',v))
  end
 end
end
for _,y in ipairs{-1,0,0.1,0.5,1,2} do print(string.format('pwl %.12f',m.pwl(y,{0,0.5,1},{0.001,0.01,0.002}))) end
assert(m.sigma(.01,0,.35,1,0,1,true)==0)
assert(m.sigma(.01,0,.35,1,1,1,false)==0)
assert(not pcall(m.pwl,.5,{0,0},{1,2}))
assert(not pcall(m.cell,0,1080,1,1,.001,1))
assert(not pcall(m.cell,480,math.huge,1,1,.001,1))
