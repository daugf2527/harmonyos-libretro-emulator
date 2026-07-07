pico-8 cartridge // http://www.pico-8.com
version 29
__lua__
function _init() cls() x=64 y=64 dx=1 dy=1 end
function _update() x+=dx y+=dy if(x<0 or x>127) dx=-dx if(y<0 or y>127) dy=-dy end
function _draw() circfill(x,y,5,8+t()%8) print('TEST ROM', 48, 60, 7) end
