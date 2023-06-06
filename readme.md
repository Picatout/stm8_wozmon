# STM8 WOZMON
Comme j'étais en train d'étudier le code source du moniteur installé sur le [Apple I](applei.1976.operatiion-manual.pdf), communément appellé WOZMON parce que ce petit programme a été écris par Steve Wozniak, 
je me suis demandé combien d'octets le même programme occuperait sur un STM8.  L'architecture matérielle du processeur STM8 est un extension de celle du 6502 utilisé sur le Apple I. Le WOZMON a une taille de 248 octets.  
Le programme sera testé sur une carte NUCLEO-S207K8.
Pour le STM8 la table des vecteurs d'interruptions occupe 128 octets. Cette taille ainsi que celle du code contenu dans [termio.asm](termio.asm) et [hardware_init.asm](hardware_init.asm) ne sera pas comptée.



