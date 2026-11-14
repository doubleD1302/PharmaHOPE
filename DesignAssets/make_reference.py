"""Render an editable SVG design reference. This is NOT an iOS screenshot."""
from pathlib import Path
from html import escape
import subprocess

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / 'review/redesign'
OUT.mkdir(parents=True, exist_ok=True)
parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1180" viewBox="0 0 1600 1180">',
         '<style>text{font-family:Segoe UI,Arial,sans-serif} .ink{fill:#173C32}.muted{fill:#5D7169}</style>']
def rect(x,y,w,h,fill,r=0,stroke=None):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+'/>')
def text(x,y,value,size=16,fill='#173C32',weight=400):
    parts.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{weight}">{escape(value)}</text>')
def line(x1,y1,x2,y2,color,width=1):
    parts.append(f'<path d="M{x1} {y1}L{x2} {y2}" stroke="{color}" stroke-width="{width}" fill="none" stroke-linecap="round"/>')
def circle(x,y,r,color,stroke=None):
    parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}"'+(f' stroke="{stroke}" stroke-width="1.5"' if stroke else '')+'/>')
def art(name,x,y,w,h):
    svg=(HERE/name).read_text()
    svg=svg.replace('<svg ',f'<svg x="{x}" y="{y}" ',1)
    import re
    svg=re.sub(r'width="\d+"',f'width="{w}"',svg,count=1)
    svg=re.sub(r'height="\d+"',f'height="{h}"',svg,count=1)
    parts.append(svg)
def pill(x,y,label,fill='#FCECE7',ink='#A8473E'):
    rect(x,y,len(label)*6.8+20,25,fill,12)
    text(x+10,y+17,label,12,ink,600)

rect(0,0,1600,1180,'#EDF1E9')
art('hope-symbol.svg',48,38,54,54)
text(119,75,'Hope',38,weight=650)
text(48,140,'Gọn công việc. Nhẹ ca trực.',38,weight=600)
text(48,176,'THAM CHIẾU THIẾT KẾ iOS · Chưa render bằng Xcode hoặc trên iPhone',16)

def phone(x,title,dark=False,tab=0):
    parts.append(f'<g transform="translate({x} 220)">')
    rect(-5,-5,370,810,'#D8E1D8',49)
    rect(0,0,360,800,'#101C19' if dark else '#F6F7F2',44)
    parts.append('<clipPath id="clip'+str(x)+'"><rect width="360" height="800" rx="44"/></clipPath><g clip-path="url(#clip'+str(x)+')">')
    text(25,32,'9:41',13,'#EDF4EE' if dark else '#173C32',600)
    rect(134,14,92,26,'#0C1512',13)
    text(302,32,'•••',14,'#EDF4EE' if dark else '#173C32',600)
    art('hope-symbol.svg',22,59,28,28)
    text(61,80,title,17,'#EDF4EE' if dark else '#173C32',650)
    circle(321,74,18,'#233832' if dark else '#EDF2EB')
    text(312,79,'≡',19,'#B2C2B8' if dark else '#5D7169')

def bottom(tab=0,dark=False,compose=False):
    bg='#192925' if dark else '#FFFFFF'
    ink='#A1DDBC' if dark else '#216754'
    if compose:
        rect(0,686,360,61,'#101C19' if dark else '#F6F7F2')
        rect(20,688,320,51,bg,18,'#334C42' if dark else '#DFE8E0')
        text(37,720,'Thêm một việc cần làm…',14,'#B2C2B8' if dark else '#5D7169')
        rect(289,694,42,39,ink,13)
        text(302,720,'+',23,'#153F32' if dark else '#FFFFFF')
    rect(0,748,360,52,bg)
    line(0,748,360,748,'#334C42' if dark else '#DFE8E0')
    circle(105,766,7,'none',ink if tab==0 else '#819489')
    if tab==0: line(102,766,105,769,ink,1.3); line(105,769,110,762,ink,1.3)
    rect(246,759,15,14,'none',3,ink if tab==1 else '#819489')
    text(81,788,'Hôm nay',11,ink if tab==0 else '#819489',600)
    text(234,788,'Lịch ca',11,ink if tab==1 else '#819489',600)
    rect(126,793,108,4,'#B2C2B8' if dark else '#173C32',2)
    parts.append('</g></g>')

phone(48,'Hope')
text(22,124,'Thứ Bảy, 14 tháng 11',14,'#5D7169')
text(22,166,'Hôm nay của bạn.',31,weight=600)
rect(20,191,320,189,'#184F41',26)
text(41,219,'CA ĐANG TRỰC',11,'#A8D8B5',600)
text(41,251,'Ca Sáng',25,'#F6F5E9',600)
text(41,280,'Tan ca 14:00',14,'#D7E5D8')
art('hope-shift.svg',225,216,98,82)
rect(41,320,278,4,'#40725F',2);rect(41,320,166,4,'#A8D8B5',2)
text(41,351,'3/5 việc hoàn thành',12,'#F6F5E9')
text(228,351,'1 việc ưu tiên',11,'#A8D8B5')
rect(20,399,320,77,'#E8F0E5',21)
rect(35,416,43,43,'#FFFFFF',13);text(46,445,'↗',25,'#216754')
text(91,430,'Gọn việc từ Zalo',16,weight=600)
text(91,451,'Từ tin nhắn thành đầu việc.',12,'#5D7169')
text(22,518,'Việc cần làm',21,weight=600);text(160,518,'2',15,'#5D7169')
rect(20,537,320,143,'#FFFFFF',20,'#DFE8E0');circle(47,568,10,'none','#5D7169')
text(70,563,'Soát danh mục thuốc',16,weight=550);text(70,586,'cận hạn sử dụng',16,weight=550)
text(70,610,'Kiểm tra kệ và ghi chú bàn giao.',12,'#5D7169')
pill(70,630,'Ưu tiên');text(165,648,'◷  11:00',12,'#5D7169')
bottom(0,compose=True)
text(48,1065,'01 / Hôm nay',17,weight=600)

phone(446,'Lịch ca',tab=1)
text(22,135,'Tuần của bạn.',31,weight=600)
text(22,165,'Sắp xếp ca trực, chủ động mỗi ngày.',13,'#5D7169')
rect(20,189,320,193,'#FFFFFF',24,'#DFE8E0')
text(45,223,'‹',24,'#216754');text(114,222,'Tháng 11, 2026',15,weight=600);text(303,223,'›',24,'#216754')
text(139,242,'09/11 – 15/11',11,'#5D7169')
for idx,(label,num) in enumerate(zip(['T2','T3','T4','T5','T6','T7','CN'],range(9,16))):
    x=32+idx*43
    if idx==5:rect(x,257,39,75,'#216754',15)
    text(x+10,278,label,10,'#FFFFFF' if idx==5 else '#5D7169')
    text(x+11,305,str(num),16,'#FFFFFF' if idx==5 else '#173C32',600)
    if idx in [0,2,5]:circle(x+20,319,2,'#A8D8B5' if idx==5 else '#216754')
text(40,358,'Thứ Bảy, 14 tháng 11',13,'#5D7169')
for x,val,label,color in [(20,'40h','Giờ làm','#216754'),(130,'5','Ca trực','#87591F'),(240,'2','Chưa có ca','#456B82')]:
    rect(x,401,100,107,'#FFFFFF',19)
    circle(x+20,423,5,'none',color);text(x+16,458,val,23,weight=600);text(x+16,485,label,11,'#5D7169')
text(22,548,'Ca trực hôm nay',21,weight=600)
rect(20,570,320,157,'#FFFFFF',24,'#DFE8E0')
rect(38,588,44,44,'#EDF2EB',14);text(50,617,'☀',23,'#216754')
text(95,609,'Ca Sáng',20,weight=600);text(95,634,'06:00 – 14:00',14,'#5D7169');text(310,606,'…',20,'#5D7169')
text(38,662,'Kiểm đếm két tiền và nhận bàn giao.',12,'#5D7169')
rect(38,680,284,30,'#EDF2EB',10);circle(51,695,3,'#216754');text(63,700,'Đang trực',12,'#216754',600)
bottom(1)
text(446,1065,'02 / Lịch ca',17,weight=600)

phone(844,'Hope',dark=True)
text(22,124,'Thứ Bảy, 14 tháng 11',14,'#B2C2B8')
text(22,166,'Hôm nay của bạn.',31,'#EDF4EE',600)
rect(20,191,320,189,'#184F41',26)
text(41,219,'CA ĐANG TRỰC',11,'#A8D8B5',600);text(41,251,'Ca Chiều',25,'#F6F5E9',600)
text(41,280,'Tan ca 22:00',14,'#D7E5D8');art('hope-shift.svg',225,216,98,82)
rect(41,320,278,4,'#40725F',2);rect(41,320,166,4,'#A8D8B5',2)
text(41,351,'3/5 việc hoàn thành',12,'#F6F5E9');text(228,351,'1 việc ưu tiên',11,'#A8D8B5')
rect(20,399,320,77,'#233832',21);rect(35,416,43,43,'#192925',13);text(46,445,'↗',25,'#A1DDBC')
text(91,430,'Gọn việc từ Zalo',16,'#EDF4EE',600);text(91,451,'Từ tin nhắn thành đầu việc.',12,'#B2C2B8')
text(22,518,'Việc cần làm',21,'#EDF4EE',600)
rect(20,537,320,143,'#192925',20,'#334C42');circle(47,568,10,'none','#B2C2B8')
text(70,563,'Đối soát quỹ và',16,'#EDF4EE',550);text(70,586,'bàn giao cuối ca',16,'#EDF4EE',550)
text(70,610,'Ghi nhận số dư và hóa đơn.',12,'#B2C2B8');pill(70,630,'Ưu tiên','#482D2A','#FFB4A7');text(165,648,'◷  21:30',12,'#B2C2B8')
bottom(0,dark=True,compose=True)
text(844,1065,'03 / Giao diện tối',17,weight=600)

text(1250,258,'QUIET CARE',13,'#5D7169',600)
text(1250,301,'Ít nhiễu.',28,weight=600);text(1250,340,'Rõ việc.',28,weight=600)
for i,(color,label) in enumerate([('#184F41','Xanh ngọc trầm'),('#A8D8B5','Xanh lá non'),('#EDC69A','Màu mơ'),('#F6F7F2','Nền ngà')]):
    rect(1250,380+i*55,38,38,color,12,'#DFE8E0');text(1304,405+i*55,label,14)
art('hope-inbox.svg',1250,641,210,175)
text(1250,853,'Asset vector gọn nhẹ',17,weight=600)
text(1250,883,'Icon · Ca trực · Công việc',13,'#5D7169')
text(1250,926,'Font hệ thống',16,weight=600)
text(1250,953,'Chữ linh hoạt theo iPhone',13,'#5D7169')
text(48,1136,'Bản tham chiếu mỹ thuật. Kiểm chứng bố cục, bàn phím và widget thực tế cần Xcode / iPhone.',15,'#5D7169')
parts.append('</svg>')
svg=''.join(parts)
(OUT/'design-reference.svg').write_text(svg,encoding='utf-8')
script="const fs=require('fs');const {Resvg}=require(process.env.HOPE_RESVG_MODULE||'@resvg/resvg-js');fs.writeFileSync(process.argv[1],new Resvg(fs.readFileSync(0,'utf8'),{font:{defaultFontFamily:'Segoe UI'}}).render().asPng());"
subprocess.run(['node','-e',script,str(OUT/'design-reference.png')],input=svg.encode(),check=True)
print('Rendered design reference; this is not an iOS runtime screenshot.')
