# STM8 Wozmon

Comme j'étais en train d'étudier le code source du moniteur installé sur le [Apple I](applei.1976.operatiion-manual.pdf), communément appellé Wozmon parce que ce petit programme a été écris par Steve Wozniak, 
je me suis demandé combien d'octets le même programme occuperait sur un STM8.  L'architecture matérielle du processeur STM8 est un extension de celle du 6502 utilisé sur le Apple I. Le Wozmon a une taille de 254 octets. La ROM du Apple I ne faisait que 256 octets.

Dans un premier temps j'ai écris une version de ce moniteur dans mon style habituel de programmation pour voir quelle taille le binaire aurait. J'ai appellé ce programme [stm8_picmon.asm](stm8_picmon.asm) et le binaire a une taille de 364 octets.

Dans un deuxième essaie j'ai collé le plus possible au modèle du programme de Steve Wozniak et j'ai obtenue un binaire de 260 octets. 12 de plus que l'original. J'ai appellé ce programme [stm8_wozmon.asm](stm8_wozmon.asm).

Ces programmes ont étés testé sur une carte **NUCLEO-8S207K8**. 


Pour construire et flasher le binaire de la version picmon faire:
```
make -fpicmon.mak && make flash
```

Pour la version wozmon faire simplement:
```
make && make flash 
```



