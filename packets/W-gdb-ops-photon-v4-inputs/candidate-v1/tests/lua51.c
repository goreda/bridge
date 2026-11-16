#include <stdio.h>
typedef struct lua_State lua_State;
extern lua_State *luaL_newstate(void);
extern void luaL_openlibs(lua_State *);
extern int luaL_loadfile(lua_State *,const char *);
extern int lua_pcall(lua_State *,int,int,int);
extern const char *lua_tolstring(lua_State *,int,unsigned long *);
extern void lua_close(lua_State *);
int main(int n,char **v){if(n!=2)return 64;lua_State *L=luaL_newstate();luaL_openlibs(L);int r=luaL_loadfile(L,v[1]);if(!r)r=lua_pcall(L,0,0,0);if(r)fprintf(stderr,"%s\n",lua_tolstring(L,-1,0));lua_close(L);return r?1:0;}
