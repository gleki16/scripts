from datetime import datetime
from selenium import webdriver
from selenium.webdriver.common.by import By
from threading import Timer
import time

# 全局变量
url             = 'https://sys.ndhu.edu.tw/AA/CLASS/subjselect/'

name_input      = 'ContentPlaceHolder1_ed_StudNo'
passwd_input    = 'ContentPlaceHolder1_ed_pass'

login_btn       = 'ContentPlaceHolder1_BtnLogin'
logout_btn      = 'ContentPlaceHolder1_HyperLink5'
pre_sort_btn    = 'ContentPlaceHolder1_Button7'

start_add_btn   = '//*[@id="ContentPlaceHolder1_grd_subjs"]/tbody/tr['
end_add_btn     = ']/td[1]'

login_error     = '帳號或密碼錯誤'
grab_success    = '成功'

start_hour      = 12
start_minute    = 30

name    = '410935032'
passwd  = 'gugeray1314'

def main():
    test_login()

    a_ready_login = alarm()
    a_ready_login.do(ready_login, start_hour, start_minute - 5)

def test_login():
    global driver
    driver = webdriver.Firefox()
    driver.implicitly_wait(5)
    driver.get(url)
    time.sleep(0.5)

    login(driver)
    time.sleep(0.5)

    driver.find_element(By.ID, pre_sort_btn).click()
    time.sleep(0.5)

    driver.find_element(By.ID, logout_btn).click()
    driver.quit()

def ready_login():
    global driver
    driver = webdriver.Firefox()
    driver.implicitly_wait(5)
    driver.get(url)
    time.sleep(0.5)

    login(driver)
    time.sleep(0.5)

    driver.find_element(By.ID, pre_sort_btn).click()
    time.sleep(0.5)

    a_grab_lesson = alarm()
    a_grab_lesson.do(grab_lesson, start_hour, start_minute - 1, 59)

def grab_lesson():
    i = 2
    while True:
        driver.find_element(By.XPATH, start_add_btn + str(i) + end_add_btn).click()
        alert_accept()
        if alert_text.find(grab_success) != -1:
            break

    while True:
        i += 1
        try:
            driver.find_element(By.XPATH, start_add_btn + str(i) + end_add_btn).click()
            alert_accept()
        except:
            break

    print('程序结束')

class alarm:
    def __init__(self):
        pass

    def do(self, func, start_hour, start_minute, start_second = 0):
        time_now    = datetime.now()
        time_start  = time_now.replace(hour = start_hour, minute = start_minute, second = start_second, microsecond = 0)
        time_delta  = time_start - time_now
        time_secs   = time_delta.total_seconds()

        self.timer = Timer(time_secs, func)
        self.timer.start()

def login(driver):
    driver.find_element(By.ID, name_input).send_keys(name)
    driver.find_element(By.ID, passwd_input).send_keys(passwd)
    driver.find_element(By.ID, login_btn).click()
    alert_accept()
    if alert_text.find(login_error) != -1:
        driver.quit()
        print('登录失败')
        exit(1)

def alert_accept():
    global alert_text
    try:
        alert = driver.switch_to.alert
        alert_text = alert.text
        print(alert_text)
        alert.accept()
    except:
        alert_text = ''

if __name__ == '__main__':
    main()
