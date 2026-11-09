#!/usr/bin/ucode
// Diagnostic entry point. The channel coordinator owns the running control loop.
import {selftest,create_preference} from './steering.uc';
if(ARGV[0]=='--self-test'){selftest();exit(0);}
if(ARGV[0]=='--check'){create_preference({check:true,preferred:ARGV[1]}).check();exit(0);}
die('Radio Preference is owned by channel-coordinator; use its service or LuCI.\n');
