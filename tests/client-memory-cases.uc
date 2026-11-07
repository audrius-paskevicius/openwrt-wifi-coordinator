let checks=0;function check(ok,label){if(!ok)die('FAIL: '+label+'\n');checks++;}
let g={freq:5500,center:5530,width:80};
check(!length(client_avoids.entries),'new boot discards old client restrictions');
avoid_client('r','AA:BB:CC:DD:EE:01',g,T+21600);
check(client_avoided('r','aa:bb:cc:dd:ee:01',g),'case-normalized matching client is avoided');
check(!client_avoided('other','aa:bb:cc:dd:ee:01',g)&&!client_avoided('r','aa:bb:cc:dd:ee:02',g),'restriction belongs to one client and radio');
check(!client_avoided('r','aa:bb:cc:dd:ee:01',{...g,width:40}),'different placement remains eligible');
avoid_client('r','AA:BB:CC:DD:EE:01',g,T+21600);
check(length(client_avoids.entries)==1,'repeated record replaces rather than duplicates');
for(let i=0;i<300;i++)avoid_client('r','test-'+i,g,T+21600);
check(length(client_avoids.entries)==256,'private RAM memory stays bounded');
let before=writes;prune_client_avoids();
check(writes==before,'unchanged memory does not rewrite even RAM file');
T+=21601;prune_client_avoids();
check(!length(client_avoids.entries)&&writes==before+1,'expired identifiers are removed from RAM file');
print('PASS: '+checks+' client recovery memory cases\n');
