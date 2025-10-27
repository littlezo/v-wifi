# setup.sh

- 获取当前硬件 IEEE 802.11 标准生成 /etc/hostapd/hostapd.conf
1、IEEE 802.11 对应配置参考 hostapd.example.conf 示例文件
  - 标准支持优先级：802.11be (EHT) >  802.11ax (HE) > 802.11ac (VHT)  > 802.11n (HT)  > 802.11
  - hostapd.example.conf:84 ##### IEEE 802.11 related configuration 
  - hostapd.example.conf:613 ##### IEEE 802.11n related configuration
  - hostapd.example.conf:674 ##### IEEE 802.11ac related configuration
  - hostapd.example.conf:833 ##### IEEE 802.11ax related configuration
  - hostapd.example.conf:1045 ##### IEEE 802.11be related configuration
  - 支持 802.11be 和 802.11ax 时，优先使用 802.11be
2、最大支持频宽优化，根据当前硬件支持的最大频宽，自动设置最大频宽
  - 例如，支持 80MHz 和 160MHz 时，优先使用 160MHz
  - 频宽优先级： 320MHz > 160MHz > 80+80 > 80MHz > 40MHz > 20MHz
3、根据当前硬件频宽和IEEE 802.11 标准，支持硬件最大连接速率
  - EHT RX > HT HE > VHT RX  > HT RX
