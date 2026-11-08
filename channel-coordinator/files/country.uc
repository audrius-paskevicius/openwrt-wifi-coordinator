#!/usr/bin/ucode
// WRT3200ACM/WRT32X only. Copy the administrator's actual configured country;
// never invent a country, alter the regulatory database, or skip radar checks.
import * as fs from 'fs';
import * as uci from 'uci';
import {configured_country} from './policy.uc';
let board=trim(fs.readfile('/tmp/sysinfo/board_name') ?? '');
if(index(['linksys,wrt3200acm','linksys,wrt32x'],board)<0)exit(0);
let c=uci.cursor(),radios=[];
c.foreach('wireless','wifi-device',r=>push(radios,r));
let country=configured_country(radios);
if(!country){
    print('DFS country hint unchanged: all radios must have the same explicit country\n');exit(0);
}
let path='/etc/modules.d/mwifiex',old=fs.readfile(path),wanted='mwifiex reg_alpha2='+country+'\n';
if(old!=null&&!match(old,/^mwifiex reg_alpha2=[A-Z]{2}\n?$/)){
    print('DFS country hint unchanged: existing custom module settings preserved\n');exit(0);
}
if(old==wanted){print('Auxiliary driver country hint matches '+country+'\n');exit(0);}
if(ARGV[0]!='--apply'){print('Auxiliary driver country hint needs '+country+' at next boot\n');exit(0);}
if(!fs.writefile(path,wanted))die('Cannot save auxiliary driver country hint\n');
print('Saved auxiliary driver country '+country+'. A reboot is needed for the module setting to take effect.\n');
