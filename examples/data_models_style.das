options gen2
module data_models_style public
require dasrmlui/ui public

[ui_style]
def harbour_style() {
    rule(part("harbour")) { width(vw(100)); min_height(vh(100)); property("margin","0"); property("background","#ecebe5"); property("color","#233b43"); property("font-family","LatoLatin"); property("font-size","17px") }
    rule(part("heading") + ", " + part("section_title") + ", " + part("subtitle") + ", " + part("eyebrow")) { display("block") }
    rule(part("harbour")+" button") { property("display","inline-block") }
    rule(part("top")) { property("height","72px"); property("padding","0 40px"); property("background","#203c45"); property("color","#f4f2e9"); property("display","flex"); property("align-items","center"); property("justify-content","space-between") }
    rule(part("brand")) { property("font-size","19px"); property("font-weight","bold"); property("letter-spacing","2px") }
    rule(part("harbour")+" button") { property("background","#e4e4dc"); property("color","#243d44"); property("border","1px #c5cec8"); property("border-radius","5px"); property("padding","10px 16px"); property("cursor","pointer"); property("font-size","15px") }
    rule(part("harbour")+" button:hover") { property("background","#d7dcd4") }
    rule(part("harbour")+" button:focus") { property("border-color","#b97524") }
    rule(part("top")+" button") { property("background","#34545b"); property("color","#fff7df"); property("border-color","#4f6e70") }
    rule(part("intro")) { property("padding","32px 40px 25px") }
    rule(part("eyebrow")) { property("font-size","12px"); property("font-weight","bold"); property("color","#936c36"); property("letter-spacing","2px"); property("margin-bottom","12px") }
    rule(part("heading")) { property("font-size","40px"); property("font-weight","bold"); property("margin","0 0 8px") }
    rule(part("subtitle")) { property("color","#687d7d"); property("margin","0") }
    rule(part("workspace")) { property("display","flex"); property("padding","0 40px"); property("gap","24px"); property("align-items","stretch") }
    rule(part("ledger")) { property("flex","1"); property("background","#faf9f2"); property("border","1px #d7dbd1"); property("border-radius","10px"); property("padding","24px") }
    rule(part("section")) { property("display","flex"); property("justify-content","space-between"); property("align-items","center"); property("margin-bottom","22px") }
    rule(part("section_title")) { property("font-size","24px"); property("margin","0"); property("font-weight","bold") }
    rule(part("total")) { property("color","#72837d"); property("font-size","14px") }
    rule(part("head")) { property("display","flex"); property("color","#829087"); property("font-size","11px"); property("letter-spacing","1px"); property("padding","0 12px 14px") }
    rule(part("entry")) { property("display","flex"); property("align-items","center"); property("border-top","1px #e2e4db"); property("padding","18px 12px"); property("min-height","45px") }
    rule(with_class(part("entry"),"priority")) { property("background","#fbf0d9"); property("border-left","3px #d8a44b"); property("padding-left","9px") }
    rule(part("item")) { property("flex","1") }
    rule(part("item")+" strong") { property("display","block"); property("font-size","18px") }
    rule(part("code")) { property("display","block"); property("color","#849087"); property("font-size","12px"); property("margin-top","4px") }
    rule(part("qty")) { property("width","62px"); property("font-size","18px") }
    rule(part("route")) { property("width","105px") }
    rule(part("head")+" "+part("route")) { property("width","175px") }
    rule(part("head")+" "+part("qty")) { property("font-size","11px") }
    rule(part("harbour")+" "+part("select")) { property("padding","7px 11px"); property("background","transparent") }
    rule(part("footer")) { property("display","flex"); property("align-items","center"); property("justify-content","space-between"); property("margin-top","24px") }
    rule(part("footer")+" span") { property("width","220px"); property("font-size","13px"); property("color","#829087") }
    rule(part("dispatch")) { property("width","280px"); property("padding","24px"); property("background","#fffdf5"); property("border-radius","10px"); property("border","1px #d7dbd1") }
    rule(part("dispatch")+" "+part("section_title")) { property("margin-bottom","20px") }
    rule(part("harbour")+" label") { property("display","block"); property("font-size","13px"); property("color","#6e7e74"); property("margin","14px 0 6px") }
    rule(part("harbour")+" input" + ", " + part("harbour")+" select") { property("width","254px"); property("padding","10px 12px"); property("background","#f2f3ec"); property("border","1px #d4d9ce"); property("border-radius","4px"); property("color","#203c45"); property("font-size","17px") }
    rule(part("harbour")+" input:focus" + ", " + part("harbour")+" select:focus") { property("border-color","#ba8b48") }
    rule(part("harbour")+" selectvalue") { property("padding","0") }
    rule(part("stepper")) { property("display","flex"); property("justify-content","space-between"); property("align-items","center"); property("background","#f2f3ec"); property("border-radius","4px") }
    rule(part("stepper")+" button") { property("width","24px"); property("text-align","center") }
    rule(part("check")) { property("display","flex"); property("align-items","center"); property("margin","16px 0") }
    rule(part("check")+" input") { property("width","18px"); property("height","18px"); property("padding","0"); property("margin-right","10px"); property("background","#e3e7da") }
    rule(part("check")+" input:checked") { property("background","#c49642") }
    rule(part("check")+" label") { property("margin","0") }
    rule(part("harbour")+" "+part("primary")) { property("width","244px"); property("background","#203c45"); property("color","#fff8e6"); property("text-align","center") }
    rule(part("harbour")+" "+part("primary")+":hover") { property("background","#34545b") }
    rule(part("harbour")+" "+part("primary")+"[disabled]") { property("background","#bac2b9"); property("color","#edf0e8") }
    rule(part("notice")) { property("font-size","13px"); property("margin-top","14px"); property("color","#6d7f63") }
    rule(part("status")) { property("margin","24px 40px"); property("display","flex"); property("align-items","center"); property("font-size","14px"); property("color","#61766d") }
    rule(part("dot")) { property("font-size","11px"); property("color","#fff8de"); property("background","#677f66"); property("padding","5px 8px"); property("border-radius","3px"); property("margin-right","12px") }
    rule(part("signature")) { property("margin-left","auto"); property("font-size","11px"); property("letter-spacing","1px") }
}
