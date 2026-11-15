// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack paint-shadow-layers
// @threat resource
// @expect contained
// @checklist paint-shadow-layers
// @checks liveness

export default () => (
  <div>
    <style>{`.p{width:20px;height:20px;display:inline-block;box-shadow:1px 1px 2px #025,2px 2px 4px #04a,3px 3px 6px #06f,4px 4px 8px #094,5px 5px 10px #0b9,6px 6px 12px #0de,7px 7px 14px #103,8px 8px 16px #128,9px 9px 18px #14d,10px 10px 20px #172,11px 11px 22px #197,12px 12px 24px #1bc,13px 13px 26px #1e1,14px 14px 28px #206,15px 15px 30px #22b,16px 16px 32px #250,17px 17px 34px #275,18px 18px 36px #29a,19px 19px 38px #2bf,20px 20px 40px #2e4,21px 21px 42px #309,22px 22px 44px #32e,23px 23px 46px #353,24px 24px 48px #378,25px 25px 50px #39d,26px 26px 52px #3c2,27px 27px 54px #3e7,28px 28px 56px #40c,29px 29px 58px #431,30px 30px 60px #456,31px 31px 62px #47b,32px 32px 64px #4a0,33px 33px 66px #4c5,34px 34px 68px #4ea,35px 35px 70px #50f,36px 36px 72px #534,37px 37px 74px #559,38px 38px 76px #57e,39px 39px 78px #5a3,40px 40px 80px #5c8,41px 41px 82px #5ed,42px 42px 84px #612,43px 43px 86px #637,44px 44px 88px #65c,45px 45px 90px #681,46px 46px 92px #6a6,47px 47px 94px #6cb,48px 48px 96px #6f0,49px 49px 98px #715,50px 50px 100px #73a,51px 51px 102px #75f,52px 52px 104px #784,53px 53px 106px #7a9,54px 54px 108px #7ce,55px 55px 110px #7f3,56px 56px 112px #818,57px 57px 114px #83d,58px 58px 116px #862,59px 59px 118px #887}`}</style>
    {Array.from({ length: 200 }, (_, i) => <div key={i} className="p">x</div>)}
    <Done after={4000} />
  </div>
);
