"""Multilingual language detection for English, Tamil, and Tanglish."""
from __future__ import annotations
import re
from enum import Enum

class Language(str, Enum):
    english  = "en"
    tamil    = "ta"
    tanglish = "ta-en"

TAMIL_UNICODE_RANGE = range(0x0B80, 0x0BFF + 1)

TANGLISH_KEYWORDS: frozenset[str] = frozenset({
    "arisi","pacharisi","puzhungalarisi","idli arisi","kadalai","kadalai paruppu",
    "toor dal","urad dal","moong dal","chana dal","masoor dal","rajma","karamani",
    "vengayam","thakkali","urulaikizhangu","kathrikai","vallakarai","mulakosu",
    "karot","beans","vazhakai","yam","senai","kovakkai","brinjal","pavakkai",
    "vazhaipalam","mangai","thraatchai","komankai","apple","paal","moru","vennai",
    "paneer","muttai","ennei","nallennai","thengai ennei","palmolein","vanaspathi",
    "milagai","milagai podi","manjal","jeera","jeeragam","dhania","karam","masala",
    "peringayam","karpooravalli","maavu","idli maavu","dosa maavu","atta","maida",
    "sooji","ravai","aval","sarkarai","uppu","jaggery","vellam","theneer","kaapi",
    "kappi","theyilai","horlicks","bournvita","biscuit","murukku","mixture","chips",
    "papad","saapodu","soap","shampoo","paste","podi","meen","koli","aattu kari",
    "madu kari","eral","paruppu","sambar","rasam podi","idli podi","pickles",
    "vathal","vadagam","tamarind","puli","coconut","thengai",
})

TANGLISH_MAP: dict[str, str] = {
    "aa":"ஆ","ii":"ஈ","uu":"ஊ","ee":"ஏ","ai":"ஐ","oo":"ஓ","au":"ஔ",
    "a":"அ","i":"இ","u":"உ","e":"எ","o":"ஒ",
    "kaa":"கா","ki":"கி","kee":"கீ","ku":"கு","koo":"கூ","ke":"கெ","kai":"கை","ko":"கொ","kau":"கௌ","ka":"க",
    "nga":"ங",
    "chaa":"சா","chi":"சி","chee":"சீ","chu":"சு","choo":"சூ","che":"செ","chai":"சை","cho":"சொ","chau":"சௌ","cha":"ச",
    "shaa":"ஷா","shi":"ஷி","shee":"ஷீ","shu":"ஷு","shoo":"ஷூ","she":"ஷெ","shai":"ஷை","sho":"ஷொ","shau":"ஷௌ","sha":"ஷ",
    "saa":"சா","si":"சி","see":"சீ","su":"சு","soo":"சூ","se":"செ","sai":"சை","so":"சொ","sau":"சௌ","sa":"ச",
    "naa":"நா","ni":"நி","nee":"நீ","nu":"நு","noo":"நூ","ne":"நெ","nai":"நை","no":"நொ","nau":"நௌ","na":"ந",
    "taa":"டா","ti":"டி","tee":"டீ","tu":"டு","too":"டூ","te":"டெ","tai":"டை","to":"டொ","tau":"டௌ","ta":"ட",
    "daa":"தா","di":"தி","dee":"தீ","du":"து","doo":"தூ","de":"தெ","dai":"தை","do":"தொ","dau":"தௌ","da":"த",
    "paa":"பா","pi":"பி","pee":"பீ","pu":"பு","poo":"பூ","pe":"பெ","pai":"பை","po":"பொ","pau":"பௌ","pa":"ப",
    "baa":"மா","bi":"மி","bee":"மீ","bu":"மு","boo":"மூ","be":"மெ","bai":"மை","bo":"மொ","bau":"மௌ","ba":"ம",
    "maa":"மா","mi":"மி","mee":"மீ","mu":"மு","moo":"மூ","me":"மெ","mai":"மை","mo":"மொ","mau":"மௌ","ma":"ம",
    "yaa":"யா","yi":"யி","yee":"யீ","yu":"யு","yoo":"யூ","ye":"யெ","yai":"யை","yo":"யொ","yau":"யௌ","ya":"ய",
    "raa":"ரா","ri":"ரி","ree":"ரீ","ru":"ரு","roo":"ரூ","re":"ரெ","rai":"ரை","ro":"ரொ","rau":"ரௌ","ra":"ர",
    "laa":"லா","li":"லி","lee":"லீ","lu":"லு","loo":"லூ","le":"லெ","lai":"லை","lo":"லொ","lau":"லௌ","la":"ல",
    "vaa":"வா","vi":"வி","vee":"வீ","vu":"வு","voo":"வூ","ve":"வெ","vai":"வை","vo":"வொ","vau":"வௌ","va":"வ",
    "haa":"ஹா","hi":"ஹி","hee":"ஹீ","hu":"ஹு","hoo":"ஹூ","he":"ஹெ","hai":"ஹை","ho":"ஹொ","hau":"ஹௌ","ha":"ஹ",
    "jaa":"ஜா","ji":"ஜி","jee":"ஜீ","ju":"ஜு","joo":"ஜூ","je":"ஜெ","jai":"ஜை","jo":"ஜொ","jau":"ஜௌ","ja":"ஜ",
    "kk":"க்க","tt":"ட்ட","pp":"ப்ப","cc":"ச்ச","nj":"ஞ்ச","ng":"ங்க","nd":"ந்த",
    "n":"ன்","m":"ம்","r":"ற்","l":"ல்","v":"வ்","y":"ய்",
    "k":"க்","t":"ட்","d":"த்","p":"ப்","s":"ஸ்","h":"ஹ்","j":"ஜ்",
}

_SORTED_MAP: list[tuple[str, str]] = sorted(TANGLISH_MAP.items(), key=lambda x: -len(x[0]))


def _has_tamil_unicode(text: str) -> bool:
    return any(ord(c) in TAMIL_UNICODE_RANGE for c in text)

def _has_ascii_alpha(text: str) -> bool:
    return any(c.isascii() and c.isalpha() for c in text)

def _keyword_score(text: str) -> float:
    lower = text.lower().strip()
    for kw in TANGLISH_KEYWORDS:
        if re.search(r"(?<!\w)" + re.escape(kw) + r"(?!\w)", lower):
            return 1.0
    return 0.0

def _syllable_score(text: str) -> float:
    lower = text.lower()
    ascii_len = sum(1 for c in lower if c.isascii() and c.isalpha())
    if ascii_len == 0:
        return 0.0
    covered = 0
    remaining = lower
    for key, _ in _SORTED_MAP:
        count = remaining.count(key)
        if count:
            covered += len(key) * count
            remaining = remaining.replace(key, " " * len(key))
    return min(covered / ascii_len, 1.0)

def detect_language(text: str) -> Language:
    if not text or not text.strip():
        return Language.english
    has_tamil = _has_tamil_unicode(text)
    has_ascii = _has_ascii_alpha(text)
    if has_tamil and not has_ascii:
        return Language.tamil
    if has_tamil and has_ascii:
        return Language.tanglish
    if has_ascii:
        if _keyword_score(text) > 0:
            return Language.tanglish
        if _syllable_score(text) >= 0.40:
            return Language.tanglish
    return Language.english

def transliterate_tanglish_to_tamil(text: str) -> str:
    result = text
    for eng, tam in _SORTED_MAP:
        result = re.sub(re.escape(eng), tam, result, flags=re.IGNORECASE)
    return result

def normalize_query(text: str) -> tuple[str, Language]:
    stripped = text.strip()
    lang = detect_language(stripped)
    if lang == Language.tanglish:
        return transliterate_tanglish_to_tamil(stripped), lang
    if lang == Language.tamil:
        return stripped, lang
    return stripped.lower(), lang
